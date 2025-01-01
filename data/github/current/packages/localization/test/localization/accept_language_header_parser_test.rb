# typed: true
# frozen_string_literal: true

require_relative "../fast_test_helper"

class Localization::AcceptLanguageHeaderParserTest < GitHub::TestCase
  test "sorts entries by priority" do
    result = parse("zh-CN,zh;q=0.9,en;q=0.8,zh-TW;q=0.7")

    expected = %w[
      zh-CN
      zh
      en
      zh-TW
    ]

    assert_equal expected, result
  end

  test "ignores *" do
    result = parse("*")

    expected = []

    assert_equal expected, result
  end

  private

  def parse(string)
    string = string.split(",").shuffle.join(",")
    Localization::AcceptLanguageHeaderParser.new.parse(string)
  end
end
