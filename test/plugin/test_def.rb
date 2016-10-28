require 'helper'

class NotifierOutputDefinitionTest < Test::Unit::TestCase
  TEST_DEFAULTS = {
    :tag => 'n', :tag_warn => nil, :tag_crit => nil,
    :interval_1st => 60, :repetitions_1st => 5,
    :interval_2nd => 300, :repetitions_2nd => 5,
    :interval_3rd => 1800
  }

  TEST_CONF1 = {
    'tag' => 'notify',
    'pattern' => 'name1', 'target_keys' => 'field1,field2',
    'check' => 'numeric_upward', 'warn_threshold' => '1', 'crit_threshold' => '2',
  }

  TEST_CONF2 = {
    'tag_warn' => 'warn', 'tag_crit' => 'crit',
    'pattern' => 'name2', 'target_key_pattern' => '^field\d$',
    'check' => 'string_find', 'warn_regexp' => 'WARN', 'crit_regexp' => 'CRIT',
    'interval_1st' => '5', 'repetitions_1st' => '1',
    'interval_2nd' => '6', 'repetitions_2nd' => '2',
    'interval_3rd' => '7'
  }

  def test_init
    d = Fluent::Plugin::NotifierOutput::Definition.new(TEST_CONF1, TEST_DEFAULTS)
    assert_equal 'name1', d.pattern
    assert_equal ['field1','field2'], d.target_keys
    assert_equal :upward, d.instance_eval{ @check }
    assert_equal 2.0, d.crit_threshold
    assert_equal 1.0, d.warn_threshold
    assert_equal 'notify', d.tag
    assert_nil d.tag_warn
    assert_nil d.tag_crit
    assert_equal [60, 300, 1800], d.intervals
    assert_equal [5, 5], d.repetitions

    d = Fluent::Plugin::NotifierOutput::Definition.new(TEST_CONF2, TEST_DEFAULTS)
    assert_equal 'name2', d.pattern
    assert_equal /^field\d$/, d.target_key_pattern
    assert_equal /^$/, d.exclude_key_pattern
    assert_equal :find, d.instance_eval{ @check }
    assert_equal /WARN/, d.warn_regexp
    assert_equal /CRIT/, d.crit_regexp
    assert_equal 'n', d.tag
    assert_equal 'warn', d.tag_warn
    assert_equal 'crit', d.tag_crit
    assert_equal [5, 6, 7], d.intervals
    assert_equal [1, 2], d.repetitions
  end

  def test_match
    d = Fluent::Plugin::NotifierOutput::Definition.new(TEST_CONF1, TEST_DEFAULTS)
    assert_equal true, d.match?('field1')
    assert_equal true, d.match?('field2')
    assert ! d.match?('field0')
    assert ! d.match?('field')
    assert ! d.match?('')

    d = Fluent::Plugin::NotifierOutput::Definition.new(TEST_CONF2, TEST_DEFAULTS)
    assert_equal true, d.match?('field0')
    assert_equal true, d.match?('field1')
    assert_equal true, d.match?('field9')
    assert ! d.match?('field')
    assert ! d.match?('fieldx')
    assert ! d.match?(' field0')
    assert ! d.match?('field0 ')

    d = Fluent::Plugin::NotifierOutput::Definition.new(TEST_CONF2.merge({'exclude_key_pattern' => '^field[7-9]$'}), TEST_DEFAULTS)
    assert_equal true, d.match?('field0')
    assert_equal true, d.match?('field1')
    assert ! d.match?('field7')
    assert ! d.match?('field8')
    assert ! d.match?('field9')
  end

  def test_check_numeric
    t = Time.strptime('2012-07-19 14:40:30', '%Y-%m-%d %T')
    d = Fluent::Plugin::NotifierOutput::Definition.new(TEST_CONF1, TEST_DEFAULTS)
    r = d.check('test.tag', t.to_i, {'field1' => '0.8', 'field2' => '1.5'}, 'field1')
    assert_nil r

    r = d.check('test.tag', t.to_i, {'field1' => '0.8', 'field2' => '1.5'}, 'field2')
    assert_equal "name1\ttest.tag\tfield2", r[:hashkey]
    assert_equal d, r[:match_def]
    assert_equal 'notify', r[:emit_tag]
    assert_equal 'name1', r['pattern']
    assert_equal 'test.tag', r['target_tag']
    assert_equal 'field2', r['target_key']
    assert_equal 'numeric_upward', r['check_type']
    assert_equal 'warn', r['level']
    assert_equal 1.0, r['threshold']
    assert_equal 1.5, r['value']
    assert_equal t.to_s, r['message_time']

    r = d.check('test.tag', t.to_i, {'field1' => '200', 'field2' => '1.5'}, 'field1')
    assert_equal "name1\ttest.tag\tfield1", r[:hashkey]
    assert_equal d, r[:match_def]
    assert_equal 'notify', r[:emit_tag]
    assert_equal 'name1', r['pattern']
    assert_equal 'test.tag', r['target_tag']
    assert_equal 'field1', r['target_key']
    assert_equal 'numeric_upward', r['check_type']
    assert_equal 'crit', r['level']
    assert_equal 2.0, r['threshold']
    assert_equal 200.0, r['value']
    assert_equal t.to_s, r['message_time']
  end

  def test_check_string
    t = Time.strptime('2012-07-19 14:40:30', '%Y-%m-%d %T')
    d = Fluent::Plugin::NotifierOutput::Definition.new(TEST_CONF2, TEST_DEFAULTS)
    r = d.check('test.tag', t.to_i, {'field0' => 'hoge pos', 'field1' => 'CRIT fooooooo baaaaarrrrrrr'}, 'field0')
    assert_nil r

    r = d.check('test.tag', t.to_i, {'field0' => 'hoge pos', 'field1' => 'CRIT fooooooo baaaaarrrrrrr'}, 'field1')
    assert_equal "name2\ttest.tag\tfield1", r[:hashkey]
    assert_equal d, r[:match_def]
    assert_equal 'crit', r[:emit_tag]
    assert_equal 'name2', r['pattern']
    assert_equal 'test.tag', r['target_tag']
    assert_equal 'field1', r['target_key']
    assert_equal 'string_find', r['check_type']
    assert_equal 'crit', r['level']
    assert_equal '/CRIT/', r['regexp']
    assert_equal 'CRIT fooooooo baaaaarrrrrrr', r['value']
    assert_equal t.to_s, r['message_time']

    r = d.check('test.tag', t.to_i, {'field0' => 'hoge pos (WARN) check!', 'field1' => 'CRIT fooooooo baaaaarrrrrrr'}, 'field0')
    assert_equal "name2\ttest.tag\tfield0", r[:hashkey]
    assert_equal d, r[:match_def]
    assert_equal 'warn', r[:emit_tag]
    assert_equal 'name2', r['pattern']
    assert_equal 'test.tag', r['target_tag']
    assert_equal 'field0', r['target_key']
    assert_equal 'string_find', r['check_type']
    assert_equal 'warn', r['level']
    assert_equal '/WARN/', r['regexp']
    assert_equal 'hoge pos (WARN) check!', r['value']
    assert_equal t.to_s, r['message_time']
  end
end
