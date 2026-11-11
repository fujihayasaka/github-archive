# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Definitions
    # Demo rule implementation using the advanced overrides UI
    class AdvancedToggleDefinition < ToggleSettingDefinition
      SupportedResource = type_member { { fixed: T.any(Organization, Repository) } }
      ResultType = type_member { { fixed: Value } }

      sig { params(setting_name: String, display_name: String, description: String, providers: T::Array[String]).void }
      def initialize(setting_name:, display_name:, description:, providers:)
        super(
          setting_name: setting_name,
          display_name: display_name,
          description: description,
          ui_component: "toggle_with_targeting",
          providers: providers,
          resource_definitions: [
            SettingsCoreV2::Resources::RepositoryDefinition.new,
            SettingsCoreV2::Resources::OrganizationDefinition.new,
          ],
          options: [
            OptionDescriptor.new(
              value: "enabled",
              label: "Enabled",
            ),
            OptionDescriptor.new(
              value: "disabled",
              label: "Disabled",
            ),
            OptionDescriptor.new(
              value: "not_set",
              label: "Not set",
            ),
          ]
        )
      end

      sig { override.returns(T::Array[SettingsCoreV2::RuleDefinition[ResultType]]) }
      def rule_definitions
        [
          OverrideRule.new(
            applies_to: SettingsCoreV2::ResourceDefinition::ResourceType::REPOSITORY,
            targeting_attributes: [
              SettingsCoreV2::RuleDefinition::TargetingAttributeDescriptor.new(
                attribute: "repository.name",
                display_name: "Repository name",
                operations: [IConditionExpression::Operation::EQ, IConditionExpression::Operation::IN],
                value_type: SettingsCoreV2::RuleDefinition::ValueType::SEARCH,
              ),
              SettingsCoreV2::RuleDefinition::TargetingAttributeDescriptor.new(
                attribute: "repository.custom_properties",
                display_name: "Repository custom property",
                operations: [IConditionExpression::Operation::EQ, IConditionExpression::Operation::IN],
                value_type: SettingsCoreV2::RuleDefinition::ValueType::SELECT,
              ),
              SettingsCoreV2::RuleDefinition::TargetingAttributeDescriptor.new(
                attribute: "repository.id",
                display_name: "Repository",
                operations: [IConditionExpression::Operation::IN],
                value_type: SettingsCoreV2::RuleDefinition::ValueType::SEARCH,
              ),
            ],
          ),
        ]
      end
    end
  end
end
