# typed: true
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class OrganizationIdTarget < ConditionTarget

      sig { override.returns(T::Boolean) }
      def internal?
        true
      end

      # Sources that support this condition target
      sig { override.returns(T::Array[Symbol]) }
      def supported_sources
        [:business]
      end

      sig { override.returns(String) }
      def target_object
        "organization"
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_ruleset_targets
        [:member_privilege]
      end

      sig do
        override.params(
          targetable: Targetable,
          ruleset_target: String,
          parameters: T.untyped
        ).returns(T::Boolean)
      end
      def run_condition(targetable, ruleset_target, parameters)
        if targetable.repository&.feature_enabled_for_source?(:emu_inherit_rulesets_from_business)
          return true if parameters["include_emu_accounts"] && targetable.repository&.is_enterprise_managed?
        end

        return false unless (organization = targetable.organization)

        parameters["organization_ids"]&.include?(organization.global_relay_id) || false
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Array.new(name: "organization_ids", display_name: "Included org IDs",
           required: true, content_type: :node_id, description: "One of these org IDs must match the org.",
           validator: method(:ensure_valid_orgs)))
        schema.add_field(ParameterSchema::Field.new(name: "include_emu_accounts", display_name: "Target all enterprise managed user accounts",
          required: false, default_value: false, type: :boolean, description: "If enabled, this condition will match all enterprise managed user accounts."))

        schema
      end

      sig do
        override.params(ruleset: RepositoryRuleset, parameters: T::Hash[String, T.untyped])
        .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
      end
      def edit_ui_metadata(ruleset, parameters)
        org_node_ids = parameters["organization_ids"]
        return nil unless org_node_ids && org_node_ids.size > 0
        return nil unless ruleset.source_type == "Business" # Enterprise

        orgs = orgs_for_node_ids(org_node_ids, ruleset.source)

        {
          organizations: orgs.map { |org| RulesEngine::ReactPayload.simple_organization_payload(org) }
        }
      end

      private

      def orgs_for_node_ids(org_node_ids, source)
        org_ids = org_node_ids.map { |id| Platform::Helpers::NodeIdentification.from_global_id(id)[1] }
        source.organizations.where(id: org_ids).active
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          org_node_ids: T::Array[String],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_orgs(context, org_node_ids, errors)
        source = context.root["ruleset_source"]
        target = context.root["ruleset_target"]

        orgs = orgs_for_node_ids(org_node_ids, source)

        errors << {
          error_code: :invalid,
          message: "organization ids cannot be empty",
        } if org_node_ids.empty?

        if orgs.size != org_node_ids.size
          errors << {
            error_code: :organization_not_available,
            message: "organization selected does not exist or is not in this enterprise",
          }
        end
      end
    end
  end
end
