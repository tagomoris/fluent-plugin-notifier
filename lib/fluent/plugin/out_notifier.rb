class Fluent::NotifierOutput < Fluent::Output
  Fluent::Plugin.register_output('notifier', self)

  NOTIFICATION_LEVELS = ['OK', 'WARN', 'CRIT', 'LOST'].freeze

  STATES_CLEAN_INTERVAL = 3600 # 1hours
  STATES_EXPIRE_SECONDS = 14400 # 4hours

  config_param :default_tag, :string, :default => 'notification'
  config_param :default_tag_warn, :string, :default => nil
  config_param :default_tag_crit, :string, :default => nil
  
  config_param :default_interval_1st, :time, :default => 60
  config_param :default_repetitions_1st, :integer, :default => 5
  config_param :default_interval_2nd, :time, :default => 300
  config_param :default_repetitions_2nd, :integer, :default => 5
  config_param :default_interval_3rd, :time, :default => 1800

  attr_accessor :defs, :states, :match_cache, :negative_cache
  
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
    @defs = []
    @states = {} # key: tag+field ?

    defaults = {
      :tag => @default_tag, :tag_warn => @default_tag_warn, :tag_crit => @default_tag_crit,
      :interval_1st => @default_interval_1st, :repetitions_1st => @default_repetitions_1st,
      :interval_2nd => @default_interval_2nd, :repetitions_2nd => @default_repetitions_2nd,
      :interval_3rd => @default_interval_3rd,
    }

    conf.elements.each do |element|
      if element.name != 'def'
        raise Fluent::ConfigError, "invalid section name for out_notifier: #{d.name}"
      end
      defs.push(Definition.new(element, defaults))
    end
  end

  def start
    super
    @mutex = Mutex.new
    @last_status_cleaned = Fluent::Engine.now
  end

  # def shutdown
  # end

  def suppressed_emit(notifications)
    notifications.each do |n|
      hashkey = n.delete(:hashkey)
      definition = n.delete(:match_def)
      tag = n.delete(:emit_tag)

      state = @states[hashkey]
      if state
        unless state.suppress?(definition, n)
          Fluent::Engine.emit(tag, Fluent::Engine.now, n)
          state.update_notified(definition, n)
        end
      else
        Fluent::Engine.emit(tag, Fluent::Engine.now, n)
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

  def emit(tag, es, chain)
    notifications = []

    es.each do |time,record|
      record.keys.each do |key|

        next if @negative_cache[key]

        defs = @match_cache[key]
        unless defs
          defs = []
          @defs.each do |d|
            defs.push(d) if d.match?(key)
          end
          if defs.size < 1
            @negative_cache[key] = true
          end
        end

        defs.each do |d|
          alert = d.check(tag, time, record, key)
          if alert
            notifications.push(alert)
          end
        end
      end
    end

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

    chain.next
  end

  class Definition
    attr_accessor :tag, :tag_warn, :tag_crit
    attr_accessor :intervals, :repetitions
    attr_accessor :pattern, :check, :target_keys, :target_key_pattern
    attr_accessor :crit_threshold, :warn_threshold # for 'numeric_upward', 'numeric_downward'
    attr_accessor :crit_regexp, :warn_regexp # for 'string_find'

    def initialize(element, defaults)
      element.keys.each do |k|
        case k
        when 'pattern'
          @pattern = element[k]
        when 'check'
          case element[k]
          when 'numeric_upward'
            @check = :upward
            @crit_threshold = element['crit_threshold'].to_f
            @warn_threshold = element['warn_threshold'].to_f
          when 'numeric_downward'
            @check = :downward
            @crit_threshold = element['crit_threshold'].to_f
            @warn_threshold = element['warn_threshold'].to_f
          when 'string_find'
            @check = :find
            @crit_regexp = Regexp.compile(element['crit_regexp'].to_s)
            @warn_regexp = Regexp.compile(element['warn_regexp'].to_s)
          else
            raise Fluent::ConfigError, "invalid check type: #{element[k]}"
          end
        when 'target_keys'
          @target_keys = element['target_keys'].split(',')
        when 'target_key_pattern'
          @target_key_pattern = Regexp.compile(element['target_key_pattern'])
        end
      end
      if @pattern.nil? or @pattern.length < 1
        raise Fluent::ConfigError, "pattern must be set"
      end
      if @target_keys.nil? and @target_key_pattern.nil?
        raise Fluent::ConfigError, "out_notifier needs one of target_keys or target_key_pattern"
      end
      @tag = element['tag'] || defaults[:tag]
      @tag_warn = element['tag_warn'] || defaults[:tag_warn]
      @tag_crit = element['tag_crit'] || defaults[:tag_crit]
      @intervals = [
                    (element['interval_1st'] || defaults[:interval_1st]),
                    (element['interval_2nd'] || defaults[:interval_2nd]),
                    (element['interval_3rd'] || defaults[:interval_3rd])
                   ]
      @repetitions = [
                      (element['repetitions_1st'] || defaults[:repetitions_1st]),
                      (element['repetitions_2nd'] || defaults[:repetitions_2nd])
                     ]
    end

    def match?(key)
      (@target_keys and @target_keys.include?(key)) or (@target_key_pattern and @target_key_pattern.match(key))
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
        if @crit_threshold and record[key].to_f >= @crit_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_crit || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_upward', 'level' => 'crit',
            'threshold' => @crit_threshold, 'value' => record[key], 'message_time' => Time.at(time).to_s
          }
        elsif @warn_threshold and record[key].to_f >= @warn_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_warn || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_upward', 'level' => 'warn',
            'threshold' => @warn_threshold, 'value' => record[key], 'message_time' => Time.at(time).to_s
          }
        else
          nil
        end
      when :downward
        if @crit_threshold and record[key].to_f <= @crit_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_crit || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_downward', 'level' => 'crit',
            'threshold' => @crit_threshold, 'value' => record[key], 'message_time' => Time.at(time).to_s
          }
        elsif @warn_threshold and record[key].to_f <= @warn_threshold
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_warn || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'numeric_downward', 'level' => 'warn',
            'threshold' => @warn_threshold, 'value' => record[key], 'message_time' => Time.at(time).to_s
          }
        else
          nil
        end
      when :find
        if @crit_regexp and @crit_regexp.match(record[key].to_s)
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_crit || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'string_find', 'level' => 'crit',
            'regexp' => @crit_regexp.inspect, 'value' => record[key], 'message_time' => Time.at(time).to_s
          }
        elsif @warn_regexp and @warn_regexp.match(record[key].to_s)
          {
            :hashkey => @pattern + "\t" + tag + "\t" + key,
            :match_def => self,
            :emit_tag => (@tag_warn || @tag),
            'pattern' => @pattern, 'target_tag' => tag, 'target_key' => key, 'check_type' => 'string_find', 'level' => 'warn',
            'regexp' => @warn_regexp.inspect, 'value' => record[key], 'message_time' => Time.at(time).to_s
          }
        else
          nil
        end
      else
        raise ArgumentError, "unknown check type (maybe bug): #{@check}"
      end
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
