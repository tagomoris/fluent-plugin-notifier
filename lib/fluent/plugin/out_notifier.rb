require "fluent/plugin/output"

class Fluent::Plugin::NotifierOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('notifier', self)

  helpers :event_emitter

  NOTIFICATION_LEVELS = ['OK', 'WARN', 'CRIT', 'LOST'].freeze

  STATES_CLEAN_INTERVAL = 3600 # 1hours
  STATES_EXPIRE_SECONDS = 14400 # 4hours

  config_param :default_tag, :string, default: 'notification'
  config_param :default_tag_warn, :string, default: nil
  config_param :default_tag_crit, :string, default: nil

  config_param :default_intervals, :array, value_type: :time, default: [60, 300, 1800]
  config_param :default_repetitions, :array, value_type: :integer, default: [5, 5]

  config_param :default_interval_1st, :time, default: nil
  config_param :default_interval_2nd, :time, default: nil
  config_param :default_interval_3rd, :time, default: nil
  config_param :default_repetitions_1st, :integer, default: nil
  config_param :default_repetitions_2nd, :integer, default: nil

  config_param :input_tag_remove_prefix, :string, default: nil

  config_section :test, multi: true, param_name: :test_configs do
    config_param :check, :enum, list: [:tag, :numeric, :regexp]
    config_param :target_key, :string, default: nil
    config_param :lower_threshold, :float, default: nil
    config_param :upper_threshold, :float, default: nil
    config_param :include_pattern, :string, default: nil
    config_param :exclude_pattern, :string, default: nil
  end

  config_section :def, multi: true, param_name: :def_configs do
    config_param :pattern, :string
    config_param :check, :enum, list: [:numeric_upward, :numeric_downward, :string_find]

    config_param :target_keys, :array, value_type: :string, default: nil
    config_param :target_key_pattern, :string, default: nil
    config_param :exclude_key_pattern, :string, default: '^$'

    config_param :tag, :string, default: nil
    config_param :tag_warn, :string, default: nil
    config_param :tag_crit, :string, default: nil

    # numeric_upward/downward
    config_param :crit_threshold, :float, default: nil
    config_param :warn_threshold, :float, default: nil

    # string_find
    config_param :crit_regexp, :string, default: nil
    config_param :warn_regexp, :string, default: nil

    # repeat & interval
    config_param :intervals, :array, value_type: :time, default: nil
    config_param :interval_1st, :time, default: nil
    config_param :interval_2nd, :time, default: nil
    config_param :interval_3rd, :time, default: nil
    config_param :repetitions, :array, value_type: :integer, default: nil
    config_param :repetitions_1st, :integer, default: nil
    config_param :repetitions_2nd, :integer, default: nil
  end

  attr_accessor :tests, :defs, :states, :match_cache, :negative_cache

  ### output
  # {
  #  'pattern' => 'http_status_errors',
  #  'target_tag' => 'httpstatus.blog',
  #  'target_key' => 'blog_5xx_percentage',
  #  'check_type' => 'numeric_upward'
  #  'level' => 'warn',
  #  'threshold' => 25,  # or 'regexp' => ....,
  #  'value' => 49,      # or 'value' => 'matched some string...',
  #  'message_time' => Time.instance
  # }

  # <match httpstatus.blog>
  #   type notifier
  #   default_tag notification
  #   default_interval_1st 1m
  #   default_repetitions_1st 5
  #   default_interval_2nd 5m
  #   default_repetitions_2nd 5
  #   default_interval_3rd 30m
  #   <test>
  #     check numeric
  #     target_key xxx
  #     lower_threshold xxx
  #     upper_threshold xxx
  #   </test>
  #   <test>
  #     check regexp
  #     target_key xxx
  #     include_pattern ^.$
  #     exclude_pattern ^.$
  #   </test>
  #   <def>
  #     pattern http_status_errors
  #     check numeric_upward
  #     warn_threshold 25
  #     crit_threshold 50
  #     tag alert
  # #    tag_warn alert.warn
  # #    tag_crit alert.crit
  #     # target_keys blog_5xx_percentage
  #     target_key_pattern ^.*_5xx_percentage$
  #   </def>
  #   <def>
  #     pattern log_checker
  #     check string_find
  #     crit_pattern 'ERROR'
  #     warn_pattern 'WARNING'
  #     tag alert
  #     # target_keys message
  #     target_key_pattern ^.*_message$
  #   </def>
  # </match>

  def configure(conf)
    super

    @match_cache = {} # cache which has map (fieldname => definition(s))
    @negative_cache = {}
    @tests = []
    @defs = []
    @states = {} # key: tag+field ?

    if @input_tag_remove_prefix
      @input_tag_remove_prefix_string = @input_tag_remove_prefix + '.'
      @input_tag_remove_prefix_length = @input_tag_remove_prefix_string.length
    end

    if @default_interval_1st || @default_interval_2nd || @default_interval_3rd
      @default_intervals = [
        @default_interval_1st || @default_intervals[0],
        @default_interval_2nd || @default_intervals[1],
        @default_interval_3rd || @default_intervals[2],
      ]
    end
    if @default_repetitions_1st || @default_repetitions_2nd
      @default_repetitions = [
        @default_repetitions_1st || @default_repetitions[0],
        @default_repetitions_2nd || @default_repetitions[1],
      ]
    end

    @test_configs.each do |test_config|
      @tests << Test.new(test_config)
    end
    @def_configs.each do |def_config|
      @defs << Definition.new(def_config, self)
    end
  end

  def start
    super
    @mutex = Mutex.new
    @last_status_cleaned = Fluent::Engine.now
  end

  def suppressed_emit(notifications)
    now = Fluent::Engine.now
    notifications.each do |n|
      hashkey = n.delete(:hashkey)
      definition = n.delete(:match_def)
      tag = n.delete(:emit_tag)

      state = @states[hashkey]
      if state
        unless state.suppress?(definition, n)
          router.emit(tag, now, n)
          state.update_notified(definition, n)
        end
      else
        router.emit(tag, now, n)
        @states[hashkey] = State.new(n)
      end
    end
  end

  def states_cleanup
    now = Fluent::Engine.now
    @states.keys.each do |key|
      if now - @states[key].last_notified > STATES_EXPIRE_SECONDS
        @states.delete(key)
      end
    end
  end

  def check(tag, es)
    notifications = []

    tag = if @input_tag_remove_prefix and
              tag.start_with?(@input_tag_remove_prefix_string) and tag.length > @input_tag_remove_prefix_length
            tag[@input_tag_remove_prefix_length..-1]
          else
            tag
          end

    es.each do |time,record|
      record.keys.each do |key|
        next if @negative_cache[key]

        defs = @match_cache[key]
        unless defs
          defs = []
          @defs.each do |d|
            defs.push(d) if d.match?(key)
          end
          @negative_cache[key] = true if defs.size < 1
        end

        defs.each do |d|
          next unless @tests.reduce(true){|r,t| r and t.test(tag, record)}

          alert = d.check(tag, time, record, key)
          if alert
            notifications.push(alert)
          end
        end
      end
    end

    notifications
  end

  def process(tag, es)
    notifications = check(tag, es)

    if notifications.size > 0
      @mutex.synchronize do
        suppressed_emit(notifications)
      end
    end

    if Fluent::Engine.now - @last_status_cleaned > STATES_CLEAN_INTERVAL
      @mutex.synchronize do
        states_cleanup
        @last_status_cleaned = Fluent::Engine.now
      end
    end
  end

  class Test
    attr_accessor :check, :target_key
    attr_accessor :lower_threshold, :upper_threshold
    attr_accessor :include_pattern, :exclude_pattern

    def initialize(section)
      @check = section.check
      @target_key = section.target_key
      case @check
      when :tag
        if !section.include_pattern && !section.exclude_pattern
          raise Fluent::ConfigError, "At least one of include_pattern or exclude_pattern must be specified for 'check tag'"
        end
        @include_pattern = section.include_pattern ? Regexp.compile(section.include_pattern) : nil
        @exclude_pattern = section.exclude_pattern ? Regexp.compile(section.exclude_pattern) : nil
      when :numeric
        if !section.lower_threshold && !section.upper_threshold
          raise Fluent::ConfigError, "At least one of lower_threshold or upper_threshold must be specified for 'check numeric'"
        end
        raise Fluent::ConfigError, "'target_key' is needed for 'check numeric'" unless @target_key
        @lower_threshold = section.lower_threshold
        @upper_threshold = section.upper_threshold
      when :regexp
        if !section.include_pattern && !section.exclude_pattern
          raise Fluent::ConfigError, "At least one of include_pattern or exclude_pattern must be specified for 'check regexp'"
        end
        raise Fluent::ConfigError, "'target_key' is needed for 'check regexp'" unless @target_key
        @include_pattern = section.include_pattern ? Regexp.compile(section.include_pattern) : nil
        @exclude_pattern = section.exclude_pattern ? Regexp.compile(section.exclude_pattern) : nil
      else
        raise "BUG: unknown check: #{@check}"
      end
    end

    def test(tag, record)
      v = case @check
          when :numeric, :regexp
            record[@target_key]
          when :tag
            tag
          end
      return false if v.nil?

      case @check
      when :numeric
        v = v.to_f
        (@lower_threshold.nil? or @lower_threshold <= v) and (@upper_threshold.nil? or v <= @upper_threshold)
      when :tag, :regexp
        v = v.to_s.force_encoding('ASCII-8BIT')
        ((@include_pattern.nil? or @include_pattern.match(v)) and (@exclude_pattern.nil? or (not @exclude_pattern.match(v)))) or false
      end
    end
  end

  class Definition
    attr_accessor :tag, :tag_warn, :tag_crit
    attr_accessor :intervals, :repetitions
    attr_accessor :pattern, :target_keys, :target_key_pattern, :exclude_key_pattern
    attr_accessor :crit_threshold, :warn_threshold # for 'numeric_upward', 'numeric_downward'
    attr_accessor :crit_regexp, :warn_regexp # for 'string_find'

    def initialize(section, plugin)
      @pattern = section.pattern

      @tag = section.tag || plugin.default_tag
      @tag_warn = section.tag_warn || plugin.default_tag_warn
      @tag_crit = section.tag_crit || plugin.default_tag_crit

      @target_keys = section.target_keys
      @target_key_pattern = section.target_key_pattern ? Regexp.compile(section.target_key_pattern) : nil
      @exclude_key_pattern = section.exclude_key_pattern ? Regexp.compile(section.exclude_key_pattern) : nil
      if !@target_keys and !@target_key_pattern
        raise Fluent::ConfigError, "out_notifier needs one of target_keys or target_key_pattern in <def>"
      end

      case section.check
      when :numeric_upward
        @check = :upward
        if !section.crit_threshold || !section.warn_threshold
          raise Fluent::ConfigError, "Both of crit_threshold and warn_threshold must be specified for 'check numeric_upward'"
        end
        @crit_threshold = section.crit_threshold
        @warn_threshold = section.warn_threshold
      when :numeric_downward
        @check = :downward
        if !section.crit_threshold || !section.warn_threshold
          raise Fluent::ConfigError, "Both of crit_threshold and warn_threshold must be specified for 'check numeric_downward'"
        end
        @crit_threshold = section.crit_threshold
        @warn_threshold = section.warn_threshold
      when :string_find
        @check = :find
        if !section.crit_regexp || !section.warn_regexp
          raise Fluent::ConfigError, "Both of crit_regexp and warn_regexp must be specified for 'check string_find'"
        end
        @crit_regexp = Regexp.compile(section.crit_regexp)
        @warn_regexp = Regexp.compile(section.warn_regexp)
      else
        raise "BUG: unknown check: #{section.check}"
      end

      @intervals = if section.intervals
                     section.intervals
                   elsif section.interval_1st || section.interval_2nd || section.interval_3rd
                     [section.interval_1st || plugin.default_intervals[0], section.interval_2nd || plugin.default_intervals[1], section.interval_3rd || plugin.default_intervals[2]]
                   else
                     plugin.default_intervals
                   end
      @repetitions = if section.repetitions
                       section.repetitions
                     elsif section.repetitions_1st || section.repetitions_2nd
                       [section.repetitions_1st || plugin.default_repetitions[0], section.repetitions_2nd || plugin.default_repetitions[1]]
                     else
                       plugin.default_repetitions
                     end
    end

    def match?(key)
      if @target_keys
        @target_keys.include?(key)
      elsif @target_key_pattern
        @target_key_pattern.match(key) and not @exclude_key_pattern.match(key)
      end
    end

    # {
    #  'pattern' => 'http_status_errors',
    #  'target_tag' => 'httpstatus.blog',
    #  'target_key' => 'blog_5xx_percentage',
    #  'check_type' => 'numeric_upward'
    #  'level' => 'warn', # 'regexp' => '[WARN] .* MUST BE CHECKED!$'
    #  'threshold' => 25,
    #  'value' => 49, # 'value' => '2012/05/15 18:01:59 [WARN] wooooops, MUST BE CHECKED!'
    #  'message_time' => Time.instance
    # }
    def check(tag, time, record, key)
      case @check
      when :upward
        value = record[key].to_f
        if @crit_threshold and value >= @crit_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_crit || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_upward', 'level' => 'crit',
            'threshold' => @crit_threshold, 'value' => value, 'message_time' => Time.at(time).to_s
          }
        elsif @warn_threshold and value >= @warn_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_warn || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_upward', 'level' => 'warn',
            'threshold' => @warn_threshold, 'value' => value, 'message_time' => Time.at(time).to_s
          }
        else
          nil
        end
      when :downward
        value = record[key].to_f
        if @crit_threshold and value <= @crit_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_crit || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_downward', 'level' => 'crit',
            'threshold' => @crit_threshold, 'value' => value, 'message_time' => Time.at(time).to_s
          }
        elsif @warn_threshold and value <= @warn_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_warn || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_downward', 'level' => 'warn',
            'threshold' => @warn_threshold, 'value' => value, 'message_time' => Time.at(time).to_s
          }
        else
          nil
        end
      when :find
        str = record[key].to_s
        if match(@crit_regexp, str)
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_crit || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'string_find', 'level' => 'crit',
            'regexp' => @crit_regexp.inspect, 'value' => str, 'message_time' => Time.at(time).to_s
          }
        elsif match(@warn_regexp, str)
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_warn || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'string_find', 'level' => 'warn',
            'regexp' => @warn_regexp.inspect, 'value' => str, 'message_time' => Time.at(time).to_s
          }
        else
          nil
        end
      else
        raise ArgumentError, "unknown check type (maybe bug): #{@check}"
      end
    end

    def match(regexp,string)
      regexp && regexp.match(string)
    rescue ArgumentError => e
      raise e unless e.message.index("invalid byte sequence in") == 0
      replaced_string = replace_invalid_byte(string)
      regexp.match(replaced_string)
    end

    def replace_invalid_byte(string)
       replace_options = { invalid: :replace, undef: :replace, replace: '?' }
       temporal_encoding = (string.encoding == Encoding::UTF_8 ? Encoding::UTF_16BE : Encoding::UTF_8)
       string.encode(temporal_encoding, string.encoding, replace_options).encode(string.encoding)
    end
  end

  class State
    # level: :warn, :crit
    # stage: 0(1st)/1(2nd)/2(3rd)
    attr_accessor :pattern, :target_tag, :target_key, :level, :stage, :counter, :first_notified, :last_notified

    def initialize(notification)
      @pattern = notification[:pattern]
      @target_tag = notification[:target_tag]
      @target_key = notification[:target_key]
      @level = notification['level']
      @stage = 0
      @counter = 1
      t = Fluent::Engine.now
      @first_notified = t
      @last_notified = t
    end

    def suppress?(definition, notification)
      if @level == notification['level']
        (Fluent::Engine.now - @last_notified) <= definition.intervals[@stage]
      else
        true
      end
    end

    def update_notified(definition, notification)
      t = Fluent::Engine.now

      if @level == notification['level']
        rep = definition.repetitions[@stage]
        if rep and rep > 0
          @counter += 1
          if @counter > rep
            @stage += 1
            @counter = 0
          end
        end
      else
        @level = notification['level']
        @stage = 0
        @counter = 1
        @first_notified = t
      end
      @last_notified = t
    end
  end
end
