# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class ModelNativeSearch
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "model_native_search"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot can search the web using model native search"
        end

        sig { returns(String) }
        def description
          "Copilot can answer questions using a model's built-in search capabilities."
        end

        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(copilot_business: Copilot::Business).returns(PolicyDescription) }
        def business_setting_description(copilot_business)
          ["If enabled, #{description}"]
        end

        sig { override.params(copilot_organization: Copilot::Organization).returns(PolicyDescription) }
        def organization_setting_description(copilot_organization)
          ["If enabled, #{description}"]
        end

        sig { override.params(copilot_user: Copilot::User).returns(PolicyDescription) }
        def user_setting_description(copilot_user)
          [description]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_model_native_search_policy, default: false)

          # not available for free plans unless GA flag is enabled
          if entity.sorbet_class == ::User
            copilot_user = T.cast(entity, Copilot::User)

            return false if copilot_user.has_limited_access? && !copilot_user.feature_flag_enabled?(:copilot_model_native_search_ga, default: false)
          end

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          # Show "Preview" label during public preview
          !entity.feature_flag_enabled?(:copilot_model_native_search_ga, default: false)
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return value(user) if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :model_native_search_setting
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :model_native_search_setting
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:unconfigured]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:unconfigured]
        end

        sig { override.params(copilot_user: Copilot::User).returns(String) }
        def user_default_value(copilot_user)
          config_values[:enabled]
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
            enabled: :MODEL_NATIVE_SEARCH_ENABLED,
            disabled: :MODEL_NATIVE_SEARCH_DISABLED,
            no_policy: :MODEL_NATIVE_SEARCH_NO_POLICY,
            unconfigured: :MODEL_NATIVE_SEARCH_UNCONFIGURED,
            unknown: :MODEL_NATIVE_SEARCH_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::ModelNativeSearch::MODEL_NATIVE_SEARCH_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::ModelNativeSearch::MODEL_NATIVE_SEARCH_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::ModelNativeSearch::MODEL_NATIVE_SEARCH_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::ModelNativeSearch::MODEL_NATIVE_SEARCH_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::ModelNativeSearch::MODEL_NATIVE_SEARCH_INVALID
          }
        end
      end
    end
  end
end
