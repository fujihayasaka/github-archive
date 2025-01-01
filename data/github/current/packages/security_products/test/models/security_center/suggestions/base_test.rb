# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    class BaseTest < GitHub::TestCase
      class TestSuggestions < Base
        sig { override.returns(T::Array[SecurityCenter::Suggestions::Suggestion]) }
        def suggestions
          []
        end
      end

      context "when no limit is provided" do
        test "it defaults to the maximum allowed limit" do
          SecurityCenter::Suggestions::Base.stub_const(:MAX_ALLOWED_SUGGESTIONS, 5) do
            suggestions = TestSuggestions.new.limit
            assert_equal(5, suggestions)
          end
        end
      end

      context "when the provided limit is less than the maximum allowed limit" do
        test "it uses the provided limit" do
          SecurityCenter::Suggestions::Base.stub_const(:MAX_ALLOWED_SUGGESTIONS, 5) do
            suggestions = TestSuggestions.new(limit: 3).limit
            assert_equal(3, suggestions)
          end
        end
      end

      context "when the provided limit is greater than the maximum allowed limit" do
        test "it sets limit to the maximum allowed limit" do
          SecurityCenter::Suggestions::Base.stub_const(:MAX_ALLOWED_SUGGESTIONS, 5) do
            suggestions = TestSuggestions.new(limit: 6).limit
            assert_equal(5, suggestions)
          end
        end
      end
    end
  end
end
