# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Orgs
      class CustomPropertyTest < GitHub::TestCase
        fixtures do
          @user = create(:user)

          @org_1 = create(:organization, admin: @user)
          @org_1_repo_1 = create(:repository, owner: @org_1)
          @org_1_repo_2 = create(:repository, owner: @org_1)
          @org_1_repo_3 = create(:repository, owner: @org_1)

          @org_1_definition_true_false = create(
            :custom_property_definition,
            :true_false,
            source: @org_1,
            property_name: SecureRandom.uuid
          )
          @org_1_definition_true_false_required = create(
            :custom_property_definition,
            :true_false,
            default_value: "true",
            source: @org_1,
            property_name: SecureRandom.uuid,
            required: true
          )

          @org_1_definition_single_select = create(
            :custom_property_definition,
            :single_select,
            allowed_values: %w[foo bar],
            source: @org_1,
            property_name: SecureRandom.uuid
          )
          @org_1_definition_single_select_required = create(
            :custom_property_definition,
            :single_select,
            allowed_values: %w[foo_1 bar_1],
            default_value: "bar_1",
            source: @org_1,
            property_name: SecureRandom.uuid,
            required: true
          )

          @org_1_definition_multi_select = create(
            :custom_property_definition,
            :multi_select,
            allowed_values: %w[foo bar],
            source: @org_1,
            property_name: SecureRandom.uuid
          )
          @org_1_definition_multi_select_required = create(
            :custom_property_definition,
            :multi_select,
            allowed_values: %w[foo_1 bar_1],
            default_value: "bar_1",
            source: @org_1,
            property_name: SecureRandom.uuid,
            required: true
          )

          @org_1_definition_string = create(
            :custom_property_definition,
            source: @org_1,
            property_name: SecureRandom.uuid
          )
          @org_1_definition_string_required = create(
            :custom_property_definition,
            default_value: "foo_1",
            source: @org_1,
            property_name: SecureRandom.uuid,
            required: true
          )
        end

        context "when no allowed repo ids are provided" do
          test "it returns no suggestions" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: [],
              name: @org_1_definition_string.property_name,
              organization: @org_1
            ).suggestions

            assert_empty(suggestions)
          end
        end

        context "when allowed repo ids is nil" do
          test "it returns all suggestions for the org" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: nil,
              name: @org_1_definition_multi_select.property_name,
              organization: @org_1
            ).suggestions

            expected = @org_1_definition_multi_select.allowed_values.map { |value| Suggestion.new(value: value) }
            assert_same_elements(expected, suggestions)
          end
        end

        context "when name is blank" do
          test "it returns no suggestions" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: "",
              organization: @org_1
            ).suggestions

            assert_empty(suggestions)
          end
        end

        context "when the custom property does not exist" do
          test "it returns no suggestions" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: SecureRandom.uuid,
              organization: @org_1
            ).suggestions

            assert_empty(suggestions)
          end
        end

        test "it does not return values for custom properties in other organizations" do
          org_2 = create(:organization, admin: @user)
          org_2_repo_1 = create(:repository, owner: org_2)
          org_2_definition_string = create(
            :custom_property_definition,
            source: org_2,
            property_name: @org_1_definition_string.property_name
          )

          org_1_repo_1_prop_assignment = create(
            :custom_property_value,
            definition: @org_1_definition_string,
            target: @org_1_repo_1,
            value: "foo_org_1_repo_1"
          )
          org_2_repo_1_prop_assignment = create(
            :custom_property_value,
            definition: org_2_definition_string,
            target: org_2_repo_1,
            value: "foo_org_2_repo_1"
          )

          suggestions = CustomProperty.new(
            allowed_repo_ids: @org_1.org_repositories.to_a + org_2.org_repositories.to_a,
            name: org_2_definition_string.property_name,
            organization: org_2
          ).suggestions

          assert_same_elements([Suggestion.new(value: org_2_repo_1_prop_assignment.value)], suggestions)
        end

        context "when the custom property type is true_false" do
          test "it returns the property's allowed values" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: @org_1_definition_true_false.property_name,
              organization: @org_1
            ).suggestions

            expected = [Suggestion.new(value: "true"), Suggestion.new(value: "false")]
            assert_same_elements(expected, suggestions)
          end

          context "when a value is provided" do
            test "it returns suggestions matching the value" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_true_false.property_name,
                organization: @org_1,
                value: "r"
              ).suggestions

              assert_same_elements([Suggestion.new(value: "true")], suggestions)
            end
          end

          context "when selected values are provided" do
            test "it returns suggestions omitting the selected values" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_true_false.property_name,
                organization: @org_1,
                selected_values: ["true"]
              ).suggestions

              assert_same_elements([Suggestion.new(value: "false")], suggestions)
            end
          end

          context "when selected values and a value are provided" do
            test "it returns suggestions matching the value and omitting the selected values" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_true_false.property_name,
                organization: @org_1,
                selected_values: ["true"],
                value: "f"
              ).suggestions

              assert_same_elements([Suggestion.new(value: "false")], suggestions)

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_true_false.property_name,
                organization: @org_1,
                selected_values: ["true"],
                value: "p"
              ).suggestions

              assert_empty(suggestions)
            end
          end

          context "limit" do
            test "it limits the number of suggestions returned" do
              limit = 1
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                limit:,
                name: @org_1_definition_true_false.property_name,
                organization: @org_1
              ).suggestions

              assert_equal(limit, suggestions.size)
            end
          end
        end

        context "when the custom property type is single_select" do
          test "it returns the property's allowed values" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: @org_1_definition_single_select.property_name,
              organization: @org_1
            ).suggestions

            expected = @org_1_definition_single_select.allowed_values.map { |value| Suggestion.new(value: value) }
            assert_same_elements(expected, suggestions)
          end

          context "when a value is provided" do
            test "it returns suggestions matching the value" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_single_select.property_name,
                organization: @org_1,
                value: @org_1_definition_single_select.allowed_values[0][1]
              ).suggestions

              assert_same_elements([Suggestion.new(value: @org_1_definition_single_select.allowed_values[0])], suggestions)
            end
          end

          context "when selected values are provided" do
            test "it returns suggestions omitting the selected values" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_single_select.property_name,
                organization: @org_1,
                selected_values: [@org_1_definition_single_select.allowed_values[0]]
              ).suggestions

              assert_same_elements([Suggestion.new(value: @org_1_definition_single_select.allowed_values[1])], suggestions)
            end
          end

          context "when selected values and a value are provided" do
            test "it returns suggestions matching the value and omitting the selected values" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_single_select.property_name,
                organization: @org_1,
                selected_values: [@org_1_definition_single_select.allowed_values[1]],
                value: @org_1_definition_single_select.allowed_values[0][0]
              ).suggestions

              assert_same_elements([Suggestion.new(value: @org_1_definition_single_select.allowed_values[0])], suggestions)
            end
          end

          test "it returns suggestions in ascending alphabetical order by value" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: @org_1_definition_single_select.property_name,
              organization: @org_1
            ).suggestions

            assert_equal(
              [
                Suggestion.new(value: @org_1_definition_single_select.allowed_values[1]),
                Suggestion.new(value: @org_1_definition_single_select.allowed_values[0])
              ],
              suggestions
            )
          end

          context "limit" do
            test "it limits the number of suggestions returned" do
              limit = 1
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                limit:,
                name: @org_1_definition_single_select.property_name,
                organization: @org_1
              ).suggestions

              assert_equal(limit, suggestions.size)
            end
          end
        end

        context "when the custom property type is multi_select" do
          test "it returns the property's allowed values" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: @org_1_definition_multi_select.property_name,
              organization: @org_1
            ).suggestions

            expected = @org_1_definition_multi_select.allowed_values.map { |value| Suggestion.new(value: value) }
            assert_same_elements(expected, suggestions)
          end

          context "when a value is provided" do
            test "it returns suggestions matching the value" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_multi_select.property_name,
                organization: @org_1,
                value: @org_1_definition_multi_select.allowed_values[0][1]
              ).suggestions

              assert_same_elements([Suggestion.new(value: @org_1_definition_multi_select.allowed_values[0])], suggestions)
            end
          end

          context "when selected values are provided" do
            test "it returns suggestions omitting the selected values" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_multi_select.property_name,
                organization: @org_1,
                selected_values: [@org_1_definition_multi_select.allowed_values[0]]
              ).suggestions

              assert_same_elements([Suggestion.new(value: @org_1_definition_multi_select.allowed_values[1])], suggestions)
            end
          end

          context "when selected values and a value are provided" do
            test "it returns suggestions matching the value and omitting the selected values" do
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_multi_select.property_name,
                organization: @org_1,
                selected_values: [@org_1_definition_multi_select.allowed_values[1]],
                value: @org_1_definition_multi_select.allowed_values[0][0]
              ).suggestions

              assert_same_elements([Suggestion.new(value: @org_1_definition_multi_select.allowed_values[0])], suggestions)
            end
          end

          test "it returns suggestions in ascending alphabetical order by value" do
            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: @org_1_definition_multi_select.property_name,
              organization: @org_1
            ).suggestions

            assert_equal(
              [
                Suggestion.new(value: @org_1_definition_multi_select.allowed_values[1]),
                Suggestion.new(value: @org_1_definition_multi_select.allowed_values[0])
              ],
              suggestions
            )
          end

          context "limit" do
            test "it limits the number of suggestions returned" do
              limit = 1
              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                limit: limit,
                name: @org_1_definition_multi_select.property_name,
                organization: @org_1
              ).suggestions

              assert_equal(limit, suggestions.size)
            end
          end
        end

        context "when the custom property type is string" do
          context "when the custom property has a default value" do
            test "the suggestions include the default value" do
              org_1_repo_1_prop_assignment = create(
                :custom_property_value,
                definition: @org_1_definition_string_required,
                target: @org_1_repo_1,
                value: "foo_org_1_repo_1"
              )

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_string_required.property_name,
                organization: @org_1
              ).suggestions

              assert_same_elements(
                [
                  Suggestion.new(value: @org_1_definition_string_required.default_value),
                  Suggestion.new(value: org_1_repo_1_prop_assignment.value)
                ],
                suggestions
              )
            end
          end

          context "when the custom property does not have a default value" do
            test "it only returns suggestions from repo assignments" do
              org_1_repo_1_prop_assignment = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_org_1_repo_1"
              )

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_string.property_name,
                organization: @org_1
              ).suggestions

              assert_same_elements([Suggestion.new(value: org_1_repo_1_prop_assignment.value)], suggestions)
            end
          end

          context "when no value is provided" do
            test "it returns suggestions" do
              org_1_repo_1_prop_assignment_1 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_1"
              )
              org_1_repo_1_prop_assignment_2 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_2"
              )

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_string.property_name,
                organization: @org_1
              ).suggestions

              assert_same_elements(
                [
                  Suggestion.new(value: org_1_repo_1_prop_assignment_1.value),
                  Suggestion.new(value: org_1_repo_1_prop_assignment_2.value)
                ],
                suggestions
              )
            end
          end

          context "when a value is provided" do
            test "it returns suggestions matching the value" do
              org_1_repo_1_prop_assignment_1 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "x_foo_prop_1"
              )
              org_1_repo_1_prop_assignment_2 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "x_foo_prop_2"
              )
              org_1_repo_1_prop_assignment_3 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "x_bar_prop_3"
              )

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_string.property_name,
                organization: @org_1,
                value: "foo"
              ).suggestions

              assert_same_elements(
                [
                  Suggestion.new(value: org_1_repo_1_prop_assignment_1.value),
                  Suggestion.new(value: org_1_repo_1_prop_assignment_2.value)
                ],
                suggestions
              )
            end
          end

          context "when selected values are provided" do
            test "it returns suggestions omitting the selected values" do
              org_1_repo_1_prop_assignment_1 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_1"
              )
              org_1_repo_1_prop_assignment_2 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_2"
              )

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_string.property_name,
                organization: @org_1,
                selected_values: ["foo_prop_1"]
              ).suggestions

              assert_same_elements([Suggestion.new(value: org_1_repo_1_prop_assignment_2.value)], suggestions)
            end
          end

          context "when selected values and a value are provided" do
            test "it returns suggestions matching the value and omitting the selected values" do
              org_1_repo_1_prop_assignment_1 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_1"
              )
              org_1_repo_1_prop_assignment_2 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_2"
              )

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                name: @org_1_definition_string.property_name,
                organization: @org_1,
                selected_values: [org_1_repo_1_prop_assignment_2.value],
                value: "foo"
              ).suggestions

              assert_same_elements([Suggestion.new(value: org_1_repo_1_prop_assignment_1.value)], suggestions)
            end
          end

          test "it returns suggestions in ascending alphabetical order by value" do
            org_1_repo_1_prop_assignment_1 = create(
              :custom_property_value,
              definition: @org_1_definition_string,
              target: @org_1_repo_1,
              value: "foo_prop_2"
            )
            org_1_repo_1_prop_assignment_2 = create(
              :custom_property_value,
              definition: @org_1_definition_string,
              target: @org_1_repo_1,
              value: "foo_prop_1"
            )

            suggestions = CustomProperty.new(
              allowed_repo_ids: @org_1.org_repositories.to_a,
              name: @org_1_definition_string.property_name,
              organization: @org_1
            ).suggestions

            assert_equal(
              [
                Suggestion.new(value: org_1_repo_1_prop_assignment_2.value),
                Suggestion.new(value: org_1_repo_1_prop_assignment_1.value)
              ],
              suggestions
            )
          end

          context "limit" do
            test "it limits the number of suggestions returned" do
              org_1_repo_1_prop_assignment_1 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_1"
              )
              org_1_repo_1_prop_assignment_2 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_2"
              )
              org_1_repo_1_prop_assignment_3 = create(
                :custom_property_value,
                definition: @org_1_definition_string,
                target: @org_1_repo_1,
                value: "foo_prop_3"
              )

              suggestions = CustomProperty.new(
                allowed_repo_ids: @org_1.org_repositories.to_a,
                limit: 2,
                name: @org_1_definition_string.property_name,
                organization: @org_1
              ).suggestions

              assert_same_elements(
                [
                  Suggestion.new(value: org_1_repo_1_prop_assignment_1.value),
                  Suggestion.new(value: org_1_repo_1_prop_assignment_2.value)
                ],
                suggestions
              )
            end
          end
        end
      end
    end
  end
end
