require 'helper'
require 'fluent/test/helpers'

class NotifierOutputStateTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  def setup
    Fluent::Test.setup
    @i = Fluent::Plugin::NotifierOutput.new
    @i.configure(config_element())
  end

  def gen_conf(hash)
    root = @i.configured_section_create(nil, config_element('root', '', {}, [config_element('def', '', hash)]))
    root.def_configs.first
  end

  TEST_DEF_CONF1 = {
    'tag' => 'notify',
    'pattern' => 'name1', 'target_keys' => 'field1,field2',
    'check' => 'numeric_upward', 'warn_threshold' => '1', 'crit_threshold' => '2',
  }
  TEST_DEF_CONF2 = {
    'tag_warn' => 'warn', 'tag_crit' => 'crit',
    'pattern' => 'name2', 'target_key_pattern' => '^field\d$',
    'check' => 'string_find', 'warn_regexp' => 'WARN', 'crit_regexp' => 'CRIT',
    'interval_1st' => '5', 'repetitions_1st' => '1',
    'interval_2nd' => '6', 'repetitions_2nd' => '2',
    'interval_3rd' => '7'
  }

  def test_init
    s = Fluent::Plugin::NotifierOutput::State.new({
        :pattern => 'name1', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'
      })
    assert_equal('name1', s.pattern)
    assert_equal('test.tag', s.target_tag)
    assert_equal('field1', s.target_key)
    assert_equal('warn', s.level)
    assert_equal(0, s.stage)
    assert_equal(1, s.counter)
    assert { s.first_notified <= Fluent::Engine.now }
    assert { s.last_notified <= Fluent::Engine.now }
  end

  def test_suppress?
    s = Fluent::Plugin::NotifierOutput::State.new({
        :pattern => 'name1', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'
      })
    d = Fluent::Plugin::NotifierOutput::Definition.new(gen_conf(TEST_DEF_CONF1), @i)
    s.last_notified = Fluent::Engine.now - @i.default_intervals[0] + 5
    assert_equal(true, s.suppress?(d, {:pattern => 'name1', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'}))
    s.last_notified = Fluent::Engine.now - @i.default_intervals[0] - 5
    assert_equal(false, s.suppress?(d, {:pattern => 'name1', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'}))

    s = Fluent::Plugin::NotifierOutput::State.new({
        :pattern => 'name1', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'
      })
    d = Fluent::Plugin::NotifierOutput::Definition.new(gen_conf(TEST_DEF_CONF1), @i)
    assert_equal(true, s.suppress?(d, {:pattern => 'name1', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'crit'}))
  end

  def test_update_notified
    s = Fluent::Plugin::NotifierOutput::State.new({
        :pattern => 'name2', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'
      })
    d = Fluent::Plugin::NotifierOutput::Definition.new(gen_conf(TEST_DEF_CONF2), @i)

    assert_equal(0, s.stage)
    assert_equal(1, s.counter)

    s.update_notified(d, {:pattern => 'name2', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'})
    assert_equal(1, s.stage)
    assert_equal(0, s.counter)

    s.update_notified(d, {:pattern => 'name2', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'warn'})
    assert_equal(1, s.stage)
    assert_equal(1, s.counter)

    s.update_notified(d, {:pattern => 'name2', :target_tag => 'test.tag', :target_key => 'field1', 'level' => 'crit'})
    assert_equal(0, s.stage)
    assert_equal(1, s.counter)
  end
end
