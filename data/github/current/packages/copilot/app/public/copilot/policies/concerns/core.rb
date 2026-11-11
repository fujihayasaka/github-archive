# typed: strict
# frozen_string_literal: true

# The Core policy concern defines core methods that are common across all policies.

module Copilot
  module Policies
    module Concerns
      module Core
        extend T::Helpers
        include Copilot::PolicyInterface
        include Scientist

        abstract!

        # value of the policy from the configuration model
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(String) }
        def value(entity)
          configuration_value(entity)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(String) }
        def configuration_value(entity)
          ActiveRecord::Base.connected_to(role: :reading) do
            entity.configuration[config_name.to_sym]
          end
        end

        # values to check for the policy state, override these if you are using non-standard values
        # in the configuration records for your policy
        sig do override.returns({
            enabled: String,
            disabled: String,
            no_policy: String,
            unconfigured: String,
          })
        end
        def config_values
          {
            enabled: "enabled",
            disabled: "disabled",
            no_policy: "no_policy",
            unconfigured: "unconfigured",
          }
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def enabled?(entity)
          value(entity) == config_values[:enabled]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def disabled?(entity)
          value(entity) == config_values[:disabled]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def no_policy?(entity)
          value(entity) == config_values[:no_policy]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def unconfigured?(entity)
          value(entity) == config_values[:unconfigured]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def configured?(entity)
          !unconfigured?(entity)
        end

        sig { override.returns(T::Boolean) }
        def dpa_covered?
          false
        end

        # whether or not the policy can be updated/changed by the given entity
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def editable_by?(entity)
          return false unless available_for?(entity)

          case entity
          when Copilot::Business
            # generally, businesses are allowed to edit their own policies
            true
          when Copilot::Organization
            if self.is_a?(Copilot::Policies::Concerns::Organization::Mutable)
              T.bind(self, Copilot::Policies::Concerns::Organization::Mutable).editable_by_org?(entity)
            else
              false
            end
          when Copilot::User
            entity.can_modify_copilot_settings?
          end
        end

        sig { override.params(config: Copilot::Configuration, value: String).void }
        def update!(config, value)
          return unless Copilot::Configuration.defined_enums[config_name][value]
          ActiveRecord::Base.connected_to(role: :writing) do
            config.update!(config_name => value)
          end
        end

        sig { override.params(entities_id: T::Array[Integer], entity_type: String, value: String).void }
        def bulk_update!(entities_id, entity_type, value)
          return unless Copilot::Configuration.defined_enums[config_name][value]

          ActiveRecord::Base.connected_to(role: :writing) do
            Copilot::Configuration.where(configurable_type: entity_type, configurable_id: entities_id).update_all(config_name => value)
          end
        end

        # configuration defaults
        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:unconfigured]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:unconfigured]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:unconfigured]
        end

        # this shouldn't be overridden
        sig(:final) { override.params(entity: Copilot::Types::CopilotEntity).returns(String) }
        def default_value(entity)
          case entity
          when Copilot::Business
            business_default_value(entity)
          when Copilot::Organization
            # orgs that get their values from their business should default to the business value
            if self.is_a?(Copilot::Policies::Concerns::Business::Propagatable) && entity.copilot_business.present?
              case value(T.must(entity.copilot_business))
              when config_values[:enabled]
                config_values[:enabled]
              when config_values[:disabled]
                config_values[:disabled]
              else
                # fall through to the org default value if business is unconfigured or no policy
                org_default_value(entity)
              end
            else
              org_default_value(entity)
            end
          when Copilot::User
            user_default_value(entity)
          end
        end

        sig { override.returns(T::Boolean) }
        def setting_rules_supported_policy?
          false
        end

        protected

        sig do
          params(
            entity: T.any(Copilot::Types::CopilotEntity, Copilot::Public::User),
            min_cfi_plan: T.nilable(Copilot::Plans::CFI),
            min_cfb_plan: T.nilable(Copilot::Plans::CFB),
            include_trials: T::Boolean,
            control_block: T.proc.returns(T::Boolean)
          ).returns(T::Boolean)
        end
        def experimental_copilot_plan_at_least?(entity, min_cfi_plan:, min_cfb_plan:, include_trials: true, &control_block)
          if entity.feature_flag_enabled?(:copilot_policy_available_helper_experiment, default: false)
            entity_id = entity.id

            entity_type = case entity
            when Copilot::Public::User
              "User"
            else
              entity.sorbet_class.to_s
            end

            science "copilot_policy_available_helper_experiment" do |e|
              e.use { control_block.call }
              e.try { copilot_plan_at_least?(entity, min_cfi_plan:, min_cfb_plan:, include_trials:) }

              # a lottt of tests have available for checks that return true even if the user
              # does not actually have copilot access. this new method relies on having copilot access
              # most of the tests don't even test available for, it is just called and the experiment fails
              e.ignore { GitHub::AppEnvironment.test? }

              # after first experiment, most mismatches are due to policies that previously didn't
              # account for overall copilot access. ignoring that here to find any other mismatches.
              # https://github.com/github/Copilot-Controls/discussions/551
              e.ignore do
                case entity
                when Copilot::User, Copilot::Public::User
                  entity.access_type == :NO_ACCESS
                else
                  false
                end
              end

              e.context({
                policy: config_name,
                entity_id: entity_id,
                entity_type: entity_type,
              })
            end
          else
            copilot_plan_at_least?(entity, min_cfi_plan:, min_cfb_plan:, include_trials:)
          end
        end

        sig { params(entity: T.any(Copilot::Types::CopilotEntity, Copilot::Public::User), min_cfi_plan: T.nilable(Copilot::Plans::CFI), min_cfb_plan: T.nilable(Copilot::Plans::CFB), include_trials: T::Boolean).returns(T::Boolean) }
        def copilot_plan_at_least?(entity, min_cfi_plan:, min_cfb_plan:, include_trials: true)
          case entity
          when Copilot::User
            entity.copilot_plan_at_least?(min_cfi_plan:, min_cfb_plan:, include_trials:)
          when Copilot::Public::User
            plan = entity.copilot_plan_enum(include_trials: include_trials)
            return false if plan.nil?

            plan.at_least?(min_cfi_plan) || plan.at_least?(min_cfb_plan)
          when Copilot::Business
            true
          when Copilot::Organization
            if min_cfb_plan == Copilot::Plans::CFB::Business
              return true
            end

            plan = entity.copilot_plan_enum(include_trials: include_trials)
            return false if plan.nil?

            plan.at_least?(min_cfb_plan)
          else
            T.absurd(entity)
          end
        end
      end
    end
  end
end
