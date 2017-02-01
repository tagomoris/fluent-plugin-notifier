require 'helper'

class NotifierOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
  type notifier
  input_tag_remove_prefix test
  <test>
    check numeric
    target_key numfield
    lower_threshold 2.5
    upper_threshold 5000
  </test>
  <test>
    check regexp
    target_key textfield
    include_pattern Target.*
    exclude_pattern TargetC
  </test>
  <def>
    pattern pattern1
    check numeric_upward
    warn_threshold 25
    crit_threshold 50
    tag_warn alert.warn
    tag_crit alert.crit
    target_keys num1,num2,num3
  </def>
  <def>
    pattern pattern2
    check string_find
    crit_regexp ERROR
    warn_regexp WARNING
    tag alert
    target_key_pattern ^message.*$
  </def>
]

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::NotifierOutput).configure(conf)
  end

  def test_configure
    assert_nothing_raised do
      create_driver
    end
  end

  test "notify 0 events when num1 < warn_threshold and no test conditions" do
    d = create_driver
    d.run(default_tag: "test") do
      d.feed({'num1' => 20, 'message' => 'INFO'})
    end
    assert_equal(0, d.events.size)
  end

  test "notify 0 events when num1 > warn_threshold but no test conditions are satisfied" do
    d = create_driver
    d.run(default_tag: "test") do
      d.feed({'num1' => 30, 'message' => 'INFO'})
    end
    assert_equal(0, d.events.size)
  end

  test "notify 1 event when num1 > warn_threshold and satisfy test conditions" do
    d = create_driver
    d.run(default_tag: "test.input") do
      d.feed({'num1' => 30, 'message' => 'INFO', 'numfield' => '30', 'textfield' => 'TargetX'})
    end
    assert_equal(1, d.events.size)
    assert_equal('alert.warn', d.events[0][0])
    assert_equal('pattern1', d.events[0][2]['pattern'])
    assert_equal('input', d.events[0][2]['target_tag'])
    assert_equal('numeric_upward', d.events[0][2]['check_type'])
    assert_equal('warn', d.events[0][2]['level'])
    assert_equal(25.0, d.events[0][2]['threshold'])
    assert_equal(30.0, d.events[0][2]['value'])
  end

  test "notify 2 events when num1 > crit_threshold and message match warn_regexp" do
    d = create_driver
    d.run(default_tag: "test") do
      d.feed({'num1' => 60, 'message' => 'foo bar WARNING xxxxx', 'numfield' => '30', 'textfield' => 'TargetX'})
    end
    assert_equal(2, d.events.size)
    assert_equal('alert.crit', d.events[0][0])
    assert_equal('pattern1', d.events[0][2]['pattern'])
    assert_equal('test', d.events[0][2]['target_tag'])
    assert_equal('numeric_upward', d.events[0][2]['check_type'])
    assert_equal('crit', d.events[0][2]['level'])
    assert_equal(50.0, d.events[0][2]['threshold'])
    assert_equal(60.0, d.events[0][2]['value'])
    assert_equal('alert', d.events[1][0])
    assert_equal('pattern2', d.events[1][2]['pattern'])
    assert_equal('test', d.events[1][2]['target_tag'])
    assert_equal('string_find', d.events[1][2]['check_type'])
    assert_equal('warn', d.events[1][2]['level'])
    assert_equal('/WARNING/', d.events[1][2]['regexp'])
    assert_equal('foo bar WARNING xxxxx', d.events[1][2]['value'])
  end

  test "notify 0 events when test conditions are not satisfied numfield < lower_threshold" do
    d = create_driver
    d.run(default_tag: "test") do
      d.feed({'num1' => 60, 'message' => 'foo bar WARNING xxxxx', 'numfield' => '2.4', 'textfield' => 'TargetX'})
    end
    assert_equal(0, d.events.size)
  end

  test "notify 0 events when test conditions are not satisfied textfield matches exclude_pattern" do
    d = create_driver
    d.run(default_tag: "test") do
      d.feed({'num1' => 60, 'message' => 'foo bar WARNING xxxxx', 'numfield' => '20', 'textfield' => 'TargetC'})
    end
    assert_equal(0, d.events.size)
  end

  test "notify 0 events when test conditions are not satisfied textfield is missing" do
    d = create_driver
    d.run(default_tag: "test") do
      d.feed({'num1' => 60, 'message' => 'foo bar WARNING xxxxx', 'numfield' => '20'})
    end
    assert_equal(0, d.events.size)
  end

  def test_emit_invalid_byte
    invalid_utf8 = "\xff".force_encoding('UTF-8')
    d = create_driver
    assert_nothing_raised do
      d.run(default_tag: "test") do
        d.feed({'num1' => 60, 'message' => "foo bar WARNING #{invalid_utf8}", 'numfield' => '30', 'textfield' => 'TargetX'})
      end
    end
  end
end
