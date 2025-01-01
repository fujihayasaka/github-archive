# typed: true
# frozen_string_literal: true

require "test_helper"

class NoArgTestClass
  include MemexProjectView::GroupedRankedSearch::Measurable

  attr_reader :sum

  def initialize
    @sum = 0

    measure!
  end

  def execute
    measurable_execute(:method)
  end

  def method
    @sum += 1
  end
end

class WithArgsTestClass
  include MemexProjectView::GroupedRankedSearch::Measurable

  attr_reader :sum

  def initialize
    @sum = 0

    measure!
  end

  def execute(amount1, amount2)
    measurable_execute(:method, amount1, amount2)
  end

  def method(amount1, amount2)
    @sum += amount1 + amount2

    "I am a contrived return value"
  end

  def measurements
    measurable_results_in_ms
  end
end

class NotMeasurableTestClass
  include MemexProjectView::GroupedRankedSearch::Measurable

  attr_reader :sum

  def initialize
    @sum = 0
  end

  def execute
    measurable_execute(:method)
  end

  def method
    @sum += 1
  end

  def measurements
    measurable_results_in_ms
  end
end

class MeasurableTest < GitHub::TestCase
  context "method proxying" do
    test "executes method with no arguments" do
      subject = NoArgTestClass.new

      subject.execute

      assert_equal 1, subject.sum
    end

    test "executes method with arguments" do
      subject = WithArgsTestClass.new

      subject.execute(100, 51)

      assert_equal 151, subject.sum
    end
  end

  context "capturing metrics" do
    test "proxied method call runtime is stored" do
      subject = WithArgsTestClass.new

      subject.execute(100, 51)

      assert_same_elements [:method], subject.measurements.keys
    end

    test "does not store metrics if measure! is not called" do
      subject = NotMeasurableTestClass.new

      subject.execute

      assert_empty subject.measurements.keys
    end
  end
end
