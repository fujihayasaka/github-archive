# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Al
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
            "al"
          end

          sig { override.returns(String) }
          def display_name
            "Anthropic Claude Opus 4"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-claude"
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            case entity.sorbet_class.to_s
            when "User"
              user = T.cast(entity, Copilot::User)
              user.has_pro_plus_access? || user.has_cfe_access? || user.has_max_access?
            when "Organization"
              org = T.cast(entity, Copilot::Organization)
              org.copilot_plan_enterprise?
            when "Business"
              # we will always allow businesses to have this available for speed. this is checked a lot
              # this is fine because we won't propagate to cfb orgs, and at the user level we return false
              # if no cfe access
              true
            else
              false
            end
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            false
          end

          sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
          def effective_value(user, all_policies = nil)
            return "disabled" unless available_for?(user)
            return value(user) if user.has_cfi_access?

            # inherited value from org or business
            inherited_policy = user_inherited_policy(user, all_policies)

            # the inherited value will be one of enabled or disabled (or nil)
            if !inherited_policy.nil?
              inherited_policy
            else
              # if the inherited value is nil, first try and do the ea fallback.
              # if there is no fallback, the policy is unconfigured
              user.business_copilot_provider_ea_user_fallback_policy(:al) || "unconfigured"
            end
          end

          sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
          def propagate_business_updates?(business, org)
            # don't propagate to non-cfe orgs
            available_for?(org)
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
              enabled: :AL_ENABLED,
              disabled: :AL_DISABLED,
              no_policy: :AL_NO_POLICY,
              unconfigured: :AL_UNCONFIGURED,
              unknown: :AL_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::AL::AL_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::AL::AL_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::AL::AL_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::AL::AL_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::AL::AL_INVALID
            }
          end
        end
      end
    end
  end
end
