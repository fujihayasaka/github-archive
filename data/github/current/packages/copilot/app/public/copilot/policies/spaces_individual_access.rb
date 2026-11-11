# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class SpacesIndividualAccess
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
          "spaces_individual_access"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Spaces Individual Access"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/how-tos/provide-context/use-copilot-spaces"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, organization members can create individually owned",
            PolicyDescriptionChunk.new(text: "#{Spaces.display_name}.", href: documentation_url),
            "When disabled, users cannot create individual spaces.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, organization members can create individually owned #{Spaces.display_name}. When disabled, users cannot create individual spaces.",
            PolicyDescriptionChunk.new(text: "Learn more about #{Spaces.display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "If enabled, you can create individually owned",
            PolicyDescriptionChunk.new(text: "#{Spaces.display_name}.", href: documentation_url),
            "When disabled, you cannot create individual spaces.",
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          !copilot_user.has_cfi_access?
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # Available to business and organization entities across all SKUs; not configurable at the individual user level.
          # Check if spaces individual policies feature is enabled. Note this will check both the business and org
          # level, see packages/copilot/app/public/copilot/organizations/feature_enabled.rb
          entity.feature_flag_enabled?(:copilot_spaces_individual_policies_ga, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false # GA feature
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          return "enabled" if user.has_cfi_access?

          # inherited or fallback value from org or business
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
            enabled: :SPACES_INDIVIDUAL_ACCESS_ENABLED,
            disabled: :SPACES_INDIVIDUAL_ACCESS_DISABLED,
            no_policy: :SPACES_INDIVIDUAL_ACCESS_NO_POLICY,
            unconfigured: :SPACES_INDIVIDUAL_ACCESS_UNCONFIGURED,
            unknown: :SPACES_INDIVIDUAL_ACCESS_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::SpacesIndividualAccess::SPACES_INDIVIDUAL_ACCESS_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::SpacesIndividualAccess::SPACES_INDIVIDUAL_ACCESS_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::SpacesIndividualAccess::SPACES_INDIVIDUAL_ACCESS_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::SpacesIndividualAccess::SPACES_INDIVIDUAL_ACCESS_ENABLED, # default to enabled
            invalid: MonolithTwirp::Copilot::Users::V1::SpacesIndividualAccess::SPACES_INDIVIDUAL_ACCESS_INVALID
          }
        end
      end
    end
  end
end
