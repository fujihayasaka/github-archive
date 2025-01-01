# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class OrgTest < GitHub::TestCase
        fixtures do
          @org_1 = create(:organization, login: "org-apple-1")
          @org_2 = create(:organization, login: "org-banana-2")
          @org_3 = create(:organization, login: "org-apple-3")
          @org_4 = create(:organization, login: "org-banana-4")
        end

        context "when no authorized orgs are provided" do
          test "it returns an empty array" do
            suggestions = Org.new(authorized_orgs: []).suggestions

            assert_same_elements([], suggestions)
          end
        end

        test "it returns suggestions for all authorized orgs" do
          suggestions = Org.new(authorized_orgs: [@org_1]).suggestions

          expected_suggestions = [@org_1].map do |org|
            Suggestion.new(value: org.display_login)
          end

          assert_same_elements(expected_suggestions, suggestions)
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Org.new(
              authorized_orgs: [@org_1, @org_2, @org_3, @org_4],
              selected_values: [@org_1.display_login, @org_3.display_login]
            ).suggestions

            expected_suggestions = [@org_2, @org_4].map do |org|
              Suggestion.new(value: org.display_login)
            end

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        test "it returns suggestions matching the value" do
          suggestions = Org.new(
            authorized_orgs: [@org_1, @org_2, @org_3, @org_4],
            value: "apple"
          ).suggestions

          expected_suggestions = [@org_1, @org_3].map do |org|
            Suggestion.new(value: org.display_login)
          end

          assert_same_elements(expected_suggestions, suggestions)
        end

        test "it returns suggestions in ascending alphabetical order by name" do
          suggestions = Org.new(
            authorized_orgs: [@org_1, @org_2, @org_3, @org_4]
          ).suggestions

          expected_suggestions = [@org_1, @org_3, @org_2, @org_4].map do |org|
            Suggestion.new(value: org.display_login)
          end

          assert_equal(expected_suggestions, suggestions)
        end

        context "limit" do
          test "it limits the number of suggestions returned" do
            suggestions = Org.new(
              authorized_orgs: [@org_1, @org_2, @org_3, @org_4],
              limit: 2
            ).suggestions

            expected_suggestions = [@org_1, @org_3].map do |org|
              Suggestion.new(value: org.display_login)
            end

            assert_equal(expected_suggestions, suggestions)
          end
        end
      end
    end
  end
end
