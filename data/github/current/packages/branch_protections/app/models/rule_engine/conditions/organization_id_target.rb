# typed: true
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class OrganizationIdTarget < ConditionTarget
      sig { override.returns(T::Boolean) }
      def internal?
        false
      end

      def feature_flag
        :member_privilege_rulesets
      end

      # Sources that support this condition target
      sig { override.returns(T::Array[Symbol]) }
      def supported_sources
        [:business]
      end

      sig { override.returns(TargetObject) }
      def target_object
        TargetObject::Organization
      end

      sig { override.returns(T::Array[Targeting::Attribute]) }
      def targeted_attributes
        [Targeting::Attribute::Organization, Targeting::Attribute::User]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_ruleset_targets
        [:repository, :branch, :tag, :push, :actions]
      end

      sig do
        override.params(
          target_attributes: T::Hash[Targeting::Attribute, T.untyped],
          parameters: T::Hash[String, T.untyped],
        ).returns(T::Boolean)
      end
      def run_condition(target_attributes, parameters)
        if (user = target_attributes[Targeting::Attribute::User]).is_a?(User)
          return true if parameters["include_emu_accounts"] && user.is_enterprise_managed?
        end

        return false unless (organization = target_attributes[Targeting::Attribute::Organization]).is_a?(Organization)

        parameters["organization_ids"]&.include?(organization.global_relay_id) || false
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Array.new(name: "organization_ids", display_name: "Included org IDs",
           required: true, content_type: :node_id, node_id_valid_types: ["Organization"], description: "One of these org IDs must match the org.",
           validator: method(:ensure_valid_orgs)))
        schema.add_field(ParameterSchema::Field.new(name: "include_emu_accounts", display_name: "Target all enterprise managed user accounts",
          required: false, default_value: false, type: :boolean, description: "If enabled, this condition will match all enterprise managed user accounts."))

        schema
      end

      sig do
        override.params(ruleset: RuleEngine::IRuleset, parameters: T::Hash[String, T.untyped])
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
        org_ids = org_node_ids.filter_map do |id|
          begin
            Platform::Helpers::NodeIdentification.from_global_id(id)[1].to_i
          rescue Platform::Errors::NotFound
            nil
          end
        end
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
