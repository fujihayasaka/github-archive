# typed: strict
# frozen_string_literal: true

require "test_helper"

class ColorsTest < GitHub::TestCase
  test "generates a color from a string" do
    assert_nothing_raised do
      result = RepositoryActions::Colors.generate_default_color("my_action")
      assert_equal result, RepositoryActions::Colors::PRIMER_COLORS[8] # gray-dark
    end
  end

  test "doesn't throw when given a hash" do
    hash = ActiveSupport::HashWithIndifferentAccess.new
    assert_nothing_raised do
      result = RepositoryActions::Colors.generate_default_color(hash)
      assert_equal result, RepositoryActions::Colors::PRIMER_COLORS[6] # red
    end
  end

  test "stringifying the hash produces the same result as using the string directly" do
    hash = ActiveSupport::HashWithIndifferentAccess.new
    hash[:name] = "my_action"
    string_of_hash = hash.to_s

    assert_nothing_raised do
      hash_result = RepositoryActions::Colors.generate_default_color(hash)
      string_result = RepositoryActions::Colors.generate_default_color(string_of_hash)

      # Make sure the string and the hash generate equivalent results
      assert_equal hash_result, string_result
    end
  end
end
