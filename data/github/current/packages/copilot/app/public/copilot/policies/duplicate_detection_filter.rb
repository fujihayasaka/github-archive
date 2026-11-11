# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class DuplicateDetectionFilter
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

        include Copilot::Policies::Concerns::User::Cacheable

        sig { override.returns(String) }
        def config_name
          "snippy_opt_out"
        end

        sig { override.returns(String) }
        def display_name
          "Duplicate Detection Filter"
        end

        sig { override.returns(String) }
        def documentation_url
          # TODO: update documentation url
          "https://gh.io/duplicate-detection-filter"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "Control whether the Duplicate Detection filter is enabled for Copilot across your enterprise.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "Control whether the Duplicate Detection filter is enabled for Copilot within your organization.",
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "Control whether the Duplicate Detection filter is active for your Copilot suggestions.",
          ]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          entity.feature_flag_enabled?(:copilot_duplicate_detection_filter, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          !entity.feature_flag_enabled?(:copilot_duplicate_detection_filter_ga, default: false)
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          if user.has_cfi_access?
            user_value = value(user)
            return user_value unless user_value == "unconfigured"

            return "enabled"
          end

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "enabled"
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:enabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:enabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:enabled]
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :duplicate_detection_filter_setting
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :duplicate_detection_filter_setting
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
            enabled: :DUPLICATE_DETECTION_FILTER_ENABLED,
            disabled: :DUPLICATE_DETECTION_FILTER_DISABLED,
            no_policy: :DUPLICATE_DETECTION_FILTER_NO_POLICY,
            unconfigured: :DUPLICATE_DETECTION_FILTER_UNCONFIGURED,
            unknown: :DUPLICATE_DETECTION_FILTER_UNKNOWN,
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
            enabled: MonolithTwirp::Copilot::Users::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::DuplicateDetectionFilter::DUPLICATE_DETECTION_FILTER_INVALID,
          }
        end
      end
    end
  end
end
