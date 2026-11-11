# typed: strict
# frozen_string_literal: true

# Policies should include this module when they want the policy value set at the Business level to take precedence over the value set at the Organization or User levels
# See more about policy inheritance here: https://github.com/github/heart-services/blob/main/docs/copilot-in-dotcom/policy-inheritance.md

module Copilot
  module Policies
    module Inheritance
      module BusinessPrecedence
        extend T::Helpers
        include Scientist

        abstract!

        include Copilot::Policies::Inheritance::Signatures

        sig { override.params(user: Copilot::User, policy_data: T.nilable(Copilot::Users::Policies::CopilotAllPolicies), skip_ea_fallback: T::Boolean).returns(T.nilable(String)) }
        def user_inherited_policy(user, policy_data = nil, skip_ea_fallback: false)
          inherited_value = if user.feature_flag_enabled_include_parents?(:use_setting_rules_copilot_models, default: false) && setting_rules_supported_policy?
            setting_rule_policy(user)
          elsif user.feature_flag_enabled?(:setting_rules_copilot_models_experiment, default: false) && setting_rules_supported_policy?
            science "setting_rules_copilot_models_experiment" do |s|
              s.use { original_user_inherited_policy(user, policy_data) }
              s.try { setting_rule_policy(user) }
              s.context({
                policy: config_name,
                data_provided: policy_data.present?,
                policies: policy_data&.map { |policy| { type: policy[:type], config: policy[:config]&.[](config_name.to_sym) } },
                policy_user_id: user.id
              })
            end
          else
            original_user_inherited_policy(user, policy_data)
          end

          if skip_ea_fallback || inherited_value.present?
            return inherited_value
          end

          business_copilot_provider_ea_user_fallback_policy(user)
        end

        private

        sig { params(user: Copilot::User, policy_data: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def original_user_inherited_policy(user, policy_data = nil)
          policy_data ||= user.all_policies

          # Find the policy inherited from the users businesses, as well as if the rule defined has been "matched"
          biz_policy, biz_match = user_inherited_business_policy(policy_data)
          # Return the policy if we have matched
          return biz_policy if biz_match

          # Find the policy inherited from the organization, as well as if the rule defined has been "matched"
          org_policy, org_match = user_inherited_org_policy(policy_data)
          # If we have matched the organization rule, return the organization policy
          return org_policy if org_match

          # If neither rule is matched, return the business policy if it exists, otherwise return the organization policy
          biz_policy || org_policy
        end

        sig { params(user: Copilot::User).returns(T.nilable(String)) }
        def setting_rule_policy(user)
          ActiveRecord::Base.connected_to(role: :reading) do
            result = CopilotDomain.domain.settings.get_effective_value(user, Copilot::Settings::CopilotModelSetting, setting_name: "copilot.models.supported_models.#{config_name}")
            if [Settings::CopilotModelSetting::Value::UNCONFIGURED, Settings::CopilotModelSetting::Value::NO_POLICY].include?(result)
              nil
            else
              result.serialize
            end
          end
        end
      end
    end
  end
end
