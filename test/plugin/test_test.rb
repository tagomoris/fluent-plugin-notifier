require 'helper'

class NotifierOutputTestTest < Test::Unit::TestCase
  TEST_CONF1 = {
    'check' => 'numeric', 'target_key' => 'field1',
    'lower_threshold' => '1', 'upper_threshold' => '2',
  }
  TEST_CONF2 = {
    'check' => 'numeric', 'target_key' => 'field1',
    'lower_threshold' => '1',
  }
  TEST_CONF3 = {
    'check' => 'numeric', 'target_key' => 'field1',
    'upper_threshold' => '2',
  }
  TEST_CONF4 = {
    'check' => 'regexp', 'target_key' => 'field2',
    'include_pattern' => 'hoge', 'exclude_pattern' => 'pos',
  }
  TEST_CONF5 = {
    'check' => 'regexp', 'target_key' => 'field2',
    'include_pattern' => 'hoge',
  }
  TEST_CONF6 = {
    'check' => 'regexp', 'target_key' => 'field2',
    'exclude_pattern' => 'pos',
  }
  TEST_CONF7 = {
    'check' => 'tag',
    'include_pattern' => 'hoge',
    'exclude_pattern' => 'pos',
  }
  TEST_CONF8 = {
    'check' => 'tag',
    'include_pattern' => 'hoge',
  }
  TEST_CONF9 = {
    'check' => 'tag',
    'exclude_pattern' => 'pos',
  }

  def test_init
    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF1)
    assert_equal(:numeric, t.check)
    assert_equal('field1', t.target_key)
    assert_equal(1.0, t.lower_threshold)
    assert_equal(2.0, t.upper_threshold)

    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF4)
    assert_equal(:regexp, t.check)
    assert_equal('field2', t.target_key)
    assert_equal(/hoge/, t.include_pattern)
    assert_equal(/pos/, t.exclude_pattern)

    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF7)
    assert_equal(:tag, t.check)
    assert_nil t.target_key
    assert_equal(/hoge/, t.include_pattern)
    assert_equal(/pos/, t.exclude_pattern)
  end

  def test_numeric
    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF1)
    assert_equal(:numeric, t.check)
    assert_equal('field1', t.target_key)
    assert_equal(1.0, t.lower_threshold)
    assert_equal(2.0, t.upper_threshold)

    assert_equal(false, t.test('test', {'field2' => '0.5'}))
    assert_equal(false, t.test('test', {'field1' => '0.5'}))
    assert_equal(true, t.test('test', {'field1' => 1}))
    assert_equal(true, t.test('test', {'field1' => 1.999999999999999999999999999999}))
    assert_equal(true, t.test('test', {'field1' => 2.0}))
    assert_equal(false, t.test('test', {'field1' => '2.0000001'}))

    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF2)
    # TEST_CONF2 = {
    #   'check' => 'numeric', 'target_key' => 'field1',
    #   'lower_threshold' => '1',
    # }
    assert_equal(false, t.test('test', {'field2' => '0.5'}))
    assert_equal(false, t.test('test', {'field1' => '0.5'}))
    assert_equal(true, t.test('test', {'field1' => 1}))
    assert_equal(true, t.test('test', {'field1' => 1.999999999999999999999999999999}))
    assert_equal(true, t.test('test', {'field1' => 2.0}))
    assert_equal(true, t.test('test', {'field1' => '2.0000001'}))
    assert_equal(true, t.test('test', {'field1' => 10000.32}))


    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF3)
    # TEST_CONF3 = {
    #   'check' => 'numeric', 'target_key' => 'field1',
    #   'upper_threshold' => '2',
    # }
    assert_equal(false, t.test('test', {'field2' => '0.5'}))
    assert_equal(true, t.test('test', {'field1' => '0.5'}))
    assert_equal(true, t.test('test', {'field1' => 1}))
    assert_equal(true, t.test('test', {'field1' => 1.999999999999999999999999999999}))
    assert_equal(true, t.test('test', {'field1' => 2.0}))
    assert_equal(false, t.test('test', {'field1' => '2.0000001'}))
    assert_equal(false, t.test('test', {'field1' => 10000.32}))

    assert_equal(true, t.test('test', {'field1' => 0.0}))
    assert_equal(true, t.test('test', {'field1' => '-1'}))
  end

  def test_regexp
    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF4)
    assert_equal(:regexp, t.check)
    assert_equal('field2', t.target_key)
    assert_equal(/hoge/, t.include_pattern)
    assert_equal(/pos/, t.exclude_pattern)

    assert_equal(false, t.test('test', {'field1' => 'hoge foo bar'}))
    assert_equal(false, t.test('test', {'field2' => ''}))
    assert_equal(true, t.test('test', {'field2' => 'hoge foo bar'}))
    assert_equal(false, t.test('test', {'field2' => 'hoge pos foo bar'}))
    assert_equal(false, t.test('test', {'field2' => 'pos foo bar'}))
    assert_equal(false, t.test('test', {'field2' => 'pos hoge foo bar'}))
    assert_equal(true, t.test('test', {'field2' => 'hoge foo bar hoge'}))

    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF5)
    # TEST_CONF5 = {
    #   'check' => 'regexp', 'target_key' => 'field2',
    #   'include_pattern' => 'hoge',
    # }
    assert_equal(false, t.test('test', {'field1' => 'hoge foo bar'}))
    assert_equal(false, t.test('test', {'field2' => ''}))
    assert_equal(true, t.test('test', {'field2' => 'hoge foo bar'}))
    assert_equal(true, t.test('test', {'field2' => 'hoge pos foo bar'}))
    assert_equal(false, t.test('test', {'field2' => 'pos foo bar'}))
    assert_equal(true, t.test('test', {'field2' => 'pos hoge foo bar'}))
    assert_equal(true, t.test('test', {'field2' => 'hoge foo bar hoge'}))

    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF6)
    # TEST_CONF6 = {
    #   'check' => 'regexp', 'target_key' => 'field2',
    #   'exclude_pattern' => 'pos',
    # }
    assert_equal(false, t.test('test', {'field1' => 'hoge foo bar'}))
    assert_equal(true, t.test('test', {'field2' => ''}))
    assert_equal(true, t.test('test', {'field2' => 'hoge foo bar'}))
    assert_equal(false, t.test('test', {'field2' => 'hoge pos foo bar'}))
    assert_equal(false, t.test('test', {'field2' => 'pos foo bar'}))
    assert_equal(false, t.test('test', {'field2' => 'pos hoge foo bar'}))
    assert_equal(true, t.test('test', {'field2' => 'hoge foo bar hoge'}))
  end

  def test_tag
    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF7)
    # TEST_CONF7 = {
    #   'check' => 'tag',
    #   'include_pattern' => 'hoge',
    #   'exclude_pattern' => 'pos',
    # }
    assert_equal(false, t.test('test', {'field1' => 'hoge foo bar'}))
    assert_equal(true, t.test('test.hoge', {'field1' => 'hoge foo bar'}))
    assert_equal(false, t.test('test.hoge.pos', {'field1' => 'hoge foo bar'}))

    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF8)
    # TEST_CONF8 = {
    #   'check' => 'tag',
    #   'include_pattern' => 'hoge',
    # }
    assert_equal(false, t.test('test', {'field1' => 'hoge foo bar'}))
    assert_equal(true, t.test('test.hoge', {'field1' => 'hoge foo bar'}))
    assert_equal(true, t.test('test.hoge.pos', {'field1' => 'hoge foo bar'}))

    t = Fluent::Plugin::NotifierOutput::Test.new(TEST_CONF9)
    # TEST_CONF9 = {
    #   'check' => 'tag',
    #   'exclude_pattern' => 'pos',
    # }
    assert_equal(true, t.test('test', {'field1' => 'hoge foo bar'}))
    assert_equal(true, t.test('test.hoge', {'field1' => 'hoge foo bar'}))
    assert_equal(false, t.test('test.hoge.pos', {'field1' => 'hoge foo bar'}))
  end
end
