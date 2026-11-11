# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Concerns
      module ModelCore
        extend T::Helpers

        abstract!

        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable
        include Copilot::Policies::Concerns::Model::Serializable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable
        include Copilot::Policies::Concerns::Ruleable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return value(user) if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(T.nilable(Copilot::Types::Models::Category)) }
        def category
          nil
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, organizations can access the latest #{display_name} model in Copilot.",
            PolicyDescriptionChunk.new(text: "Learn more about how GitHub Copilot serves #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organization will have access to the latest #{display_name} model.",
            PolicyDescriptionChunk.new(text: "Learn more about how GitHub Copilot serves #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use the latest #{display_name} model.",
            PolicyDescriptionChunk.new(text: "Learn more about how GitHub Copilot serves #{display_name}.", href: documentation_url)
          ]
        end

        protected

        # simple wrapper around the plan check for easy progressive rollouts
        sig { params(entity: Copilot::Types::CopilotEntity, pro_flag: T.nilable(Symbol), free_flag: T.nilable(Symbol), control_block: T.proc.returns(T::Boolean)).returns(T::Boolean) }
        def progressive_rollout_available_for?(entity, pro_flag: nil, free_flag: nil, &control_block)
          cfi_plan = Copilot::Plans::CFI::ProPlus
          cfb_plan = Copilot::Plans::CFB::Enterprise

          if free_flag && entity.feature_flag_enabled?(free_flag, default: false)
            cfi_plan = Copilot::Plans::CFI::Free
            cfb_plan = Copilot::Plans::CFB::Business
          elsif pro_flag && entity.feature_flag_enabled?(pro_flag, default: false)
            cfi_plan = Copilot::Plans::CFI::Pro
            cfb_plan = Copilot::Plans::CFB::Business
          end

          experimental_copilot_plan_at_least?(entity, min_cfb_plan: cfb_plan, min_cfi_plan: cfi_plan, &control_block)
        end
      end
    end
  end
end
