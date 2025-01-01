# frozen_string_literal: true

require "test_helper"
require "normal_yaml"

class NormalYAMLTest < ActiveSupport::TestCase
  def normalize(data)
    NormalYAML.load(NormalYAML.dump(data))
  end

  def assert_normalization(data, expected)
    normalized = nil
    assert_nothing_raised { normalized = normalize(data) }
    assert_equal expected.class, normalized.class

    # Prevents deprecation warning.
    if expected.nil?
      assert_nil normalized
    else
      assert_equal expected, normalized
    end
  end

  def assert_normal(data)
    assert_normalization(data, data)
  end

  def assert_abnormal(data)
    assert_raise ArgumentError do
      normalize(data)
    end
  end

  test "stringifies and sorts hash keys" do
    assert_normalization(
      { one: 1, two: 2, three: 3 },
      { "one" => 1, "three" => 3, "two" => 2 },
    )
  end

  test "stringifies and sorts nested hash keys" do
    assert_normalization(
      {
        bananas: { one: 1, two: 2, three: 3 },
        apples: { one: 1, two: 2, three: 3 },
      },
      {
        "apples" => { "one" => 1, "three" => 3, "two" => 2 },
        "bananas" => { "one" => 1, "three" => 3, "two" => 2 },
      },
    )
  end

  test "preserves array order" do
    assert_normal(["bananas", "apples"])
  end

  test "normalizes array elements" do
    assert_normalization(
      [
        { one: 1, two: 2, three: 3 },
      ],
      [
        { "one" => 1, "three" => 3, "two" => 2 },
      ],
    )
  end

  test "handles true" do
    assert_normal true
  end

  test "handles false" do
    assert_normal false
  end

  test "handles nil" do
    assert_normal nil
  end

  test "handles integers" do
    assert_normal 42
  end

  test "handles floats" do
    assert_normal 1.23
  end

  test "handles strings" do
    assert_normal "Hello, world!"
  end

  test "handles decimals" do
    assert_normal "1.23".to_d
  end

  test "handles dates" do
    assert_normal Date.current
  end

  test "handles times" do
    assert_normal Time.now.utc
  end

  test "converts string subclasses to strings" do
    string = +"Hello, world!"
    stringish = Class.new(String).new("Hello, world!")
    normalized_string = normalize(stringish)

    assert_equal String, normalized_string.class
    assert_equal string, normalized_string
  end

  test "converts decimal subclasses to decimals" do
    decimal = BigDecimal("1.23")
    decimalish = Class.new(BigDecimal).interpret_loosely("1.23")
    normalized_decimal = normalize(decimalish)

    assert_equal BigDecimal, normalized_decimal.class
    assert_equal decimal, normalized_decimal
  end

  test "converts date subclasses to dates" do
    date = Date.new(2018, 8, 22)
    dateish = Class.new(Date).new(2018, 8, 22)
    normalized_date = normalize(dateish)

    assert_equal Date, normalized_date.class
    assert_equal date, normalized_date
  end

  test "converts time subclasses to times" do
    time = Time.utc(2018, 8, 22, 18, 2, 38)
    timeish = Class.new(Time).utc(2018, 8, 22, 18, 2, 38)
    normalized_time = normalize(timeish)

    assert_equal Time, normalized_time.class
    assert_equal time, normalized_time
  end

  test "converts times to UTC" do
    time = Time.utc(2018, 8, 22, 18, 2, 38)
    offset_time = Time.new(2018, 8, 22, 13, 2, 38, "-05:00")
    normalized_time = normalize(offset_time)

    assert_equal Time, normalized_time.class
    assert_equal time, normalized_time
    assert normalized_time.utc?
  end

  test "does not handle arbitrary classes" do
    object = Class.new(Object).new

    assert_abnormal(object)
  end
end
