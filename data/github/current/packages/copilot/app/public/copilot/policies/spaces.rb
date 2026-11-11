# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Spaces
      class << self
        include Copilot::Policy

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
          "spaces"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Spaces"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/how-tos/provide-context/use-copilot-spaces"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, organization members can view and create",
            PolicyDescriptionChunk.new(text: "#{display_name}.", href: documentation_url),
            "When disabled, users cannot view or create any #{display_name}.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organization can view and create #{display_name}. When disabled, users cannot view or create any #{display_name}.",
            PolicyDescriptionChunk.new(text: "Learn more about #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "If enabled, you can view and create",
            PolicyDescriptionChunk.new(text: "#{display_name}.", href: documentation_url),
            "When disabled, you cannot view or create any #{display_name}.",
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # Available for all SKUs: Free, Pro, Pro+, Copilot Business, Copilot Enterprise
          # Not available for user-level configuration
          return false if entity.sorbet_class == ::User

          # Check if spaces feature is enabled. Note this will check both the business and org
          # level, see packages/copilot/app/public/copilot/organizations/feature_enabled.rb
          entity.feature_flag_enabled?(:copilot_spaces_policy_ga, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false # GA feature as of 2025-09-24
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          # inherited value from org or business
          # if there is no fallback, the policy defaults to enabled (opt-out)
          user_inherited_policy(user, all_policies) || "enabled"
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
            enabled: :SPACES_ENABLED,
            disabled: :SPACES_DISABLED,
            no_policy: :SPACES_NO_POLICY,
            unconfigured: :SPACES_UNCONFIGURED,
            unknown: :SPACES_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::Spaces::SPACES_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::Spaces::SPACES_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::Spaces::SPACES_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::Spaces::SPACES_ENABLED, # default to enabled
            invalid: MonolithTwirp::Copilot::Users::V1::Spaces::SPACES_INVALID
          }
        end
      end
    end
  end
end
