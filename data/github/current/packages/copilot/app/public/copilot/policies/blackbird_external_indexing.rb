# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BlackbirdExternalIndexing
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable
        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness

        # Override org inheritance so org unconfigured/no_policy are treated as disabled for this policy.
        # This keeps semantic indexing locked down unless an org is explicitly enabled.
        sig { override.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_org_policy(policy_data)
          has_org_enabled = T.let(false, T::Boolean)

          policy_data.each do |data|
            next unless data[:type] == :organization

            config = data[:config]
            return [config_values[:disabled], true] unless config

            value = config[config_name.to_sym]
            if value == config_values[:disabled] || value == config_values[:unconfigured] || value == config_values[:no_policy]
              return [config_values[:disabled], true]
            elsif value == config_values[:enabled]
              has_org_enabled = true
            end
          end

          # Enabled is only returned when no org-level restrictive state is present.
          return [config_values[:enabled], false] if has_org_enabled

          [nil, false]
        end

        # Override business inheritance so business unconfigured is treated as disabled,
        # while business no_policy still defers to org-level resolution.
        sig { override.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_business_policy(policy_data)
          has_business_enabled = T.let(false, T::Boolean)

          policy_data.each do |data|
            next unless data[:type] == :business

            config = data[:config]
            return [config_values[:disabled], true] unless config

            value = config[config_name.to_sym]
            if value.nil? || value == config_values[:disabled] || value == config_values[:unconfigured]
              return [config_values[:disabled], true]
            elsif value == config_values[:enabled]
              has_business_enabled = true
            end
          end

          # Enabled is only returned when no business-level restrictive state is present.
          return [config_values[:enabled], false] if has_business_enabled

          [nil, false]
        end

        sig { override.returns(String) }
        def config_name
          "blackbird_external_indexing" # should match the name of the enum you defined in `configuration.rb`
        end

        # the display name of the policy in dotcom
        sig { override.returns(String) }
        def display_name
          "Semantic indexing for Non-GitHub Repositories"
        end

        # link to documentation for your feature
        sig { override.returns(String) }
        def documentation_url
          "https://code.visualstudio.com/docs/copilot/reference/workspace-context"
        end


        sig { override.params(copilot_business: Copilot::Business).returns(PolicyDescription) }
        def business_setting_description(copilot_business)
          ["If enabled, members of this business will have access to upload non-GitHub repositories for semantic indexing."]
        end

        sig { override.params(copilot_organization: Copilot::Organization).returns(PolicyDescription) }
        def organization_setting_description(copilot_organization)
          ["If enabled, members of this organization will have access to upload non-GitHub repositories for semantic indexing."]
        end

        sig { override.params(copilot_user: Copilot::User).returns(PolicyDescription) }
        def user_setting_description(copilot_user)
          ["If enabled, you will have access to upload non-GitHub repositories for semantic indexing."]
        end

        # whether or not your feature should be available for a business, org, or user.
        # NOTE: this is not whether or not the feature is enabled, but whether or not they can access
        # this feature
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          if entity.sorbet_class == ::User
            user = T.cast(entity, Copilot::User)
            if user.has_cfb_access? || user.has_cfe_access?
              return user.feature_flag_enabled_include_parents?(:blackbird_external_indexing_cfb_policy, default: false)
            end

            if user.has_cfi_access?
              return user.feature_flag_enabled?(:blackbird_external_indexing_cfi_policy, default: false)
            end

            return false
          end

          return false unless entity.is_a?(Copilot::Business) || entity.is_a?(Copilot::Organization)

          entity.feature_flag_enabled_include_parents?(:blackbird_external_indexing_cfb_policy, default: false)
        end

        # whether or not this feature is in "preview". If this is true we will show the preview badge
        # in the settings
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

        # policies are checked at the user level. this function should use any inheritance rules
        # and return the effective value for a user given their org/biz settings.
        # you will likely want to change this implementation, but this is a good starting point.
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          if user.has_cfb_access? || user.has_cfe_access?
            # inherited value from org or business
            inherited_policy = user_inherited_policy(user, all_policies)
            return "disabled" if inherited_policy.nil? || %w[unconfigured no_policy].include?(inherited_policy)

            return inherited_policy
          end

          return value(user) == "unconfigured" ? "enabled" : value(user) if user.has_cfi_access?

          "disabled"
        end

        private

        sig do override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        def instrumentation_symbols
          {
            enabled: :BLACKBIRD_EXTERNAL_INDEXING_ENABLED,
            disabled: :BLACKBIRD_EXTERNAL_INDEXING_DISABLED,
            no_policy: :BLACKBIRD_EXTERNAL_INDEXING_NO_POLICY,
            unconfigured: :BLACKBIRD_EXTERNAL_INDEXING_UNCONFIGURED,
            unknown: :BLACKBIRD_EXTERNAL_INDEXING_UNKNOWN
          }
        end

        sig do override.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer
          })
        end
        def twirp_values
          {
            enabled: MonolithTwirp::Copilot::Users::V1::BlackbirdExternalIndexing::BLACKBIRD_EXTERNAL_INDEXING_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::BlackbirdExternalIndexing::BLACKBIRD_EXTERNAL_INDEXING_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::BlackbirdExternalIndexing::BLACKBIRD_EXTERNAL_INDEXING_DISABLED, # this is invalid for users, so we just assume disabled
            unconfigured: MonolithTwirp::Copilot::Users::V1::BlackbirdExternalIndexing::BLACKBIRD_EXTERNAL_INDEXING_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::BlackbirdExternalIndexing::BLACKBIRD_EXTERNAL_INDEXING_INVALID
          }
        end
      end
    end
  end
end
