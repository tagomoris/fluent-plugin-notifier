require 'helper'

class NotifierOutputTest < Test::Unit::TestCase
  CONFIG = %[
]
  def create_driver(conf=CONFIG,tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::NotifierOutput, tag).configure(conf)
  end
end
