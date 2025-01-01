# typed: strict
# frozen_string_literal: true

# The Core policy concern defines core methods that are common across all policies.

module Copilot
  module Policies
    module Concerns
      module Core
        extend T::Helpers
        include Copilot::Policy

        abstract!

        # value of the policy from the configuration model
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(String) }
        def value(entity)
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

        # whether or not the given org's policy is inherited from the business
        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def org_policy_inherited?(org)
          # get the business config
          business = org.business
          return false unless business

          copilot_biz = Copilot::Business.new(business)
          return false if unconfigured?(copilot_biz) || no_policy?(copilot_biz)

          true
        end

        # whether or not the policy can be updated/changed by the given entity
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def editable_by?(entity)
          return false unless available_for?(entity)

          case entity.sorbet_class.to_s
          when "Business"
            # generally, businesses are allowed to edit their own policies
            true
          when "Organization"
            # orgs can edit their own policies if they are not inherited from a business
            !org_policy_inherited?(T.cast(entity, Copilot::Organization))
          when "User"
            T.cast(entity, Copilot::User).can_modify_copilot_settings?
          else
            # shouldn't get here, but just in case
            false
          end
        end

        private

        sig { override.params(config: Copilot::Configuration, value: String).void }
        def update!(config, value)
          return unless Copilot::Configuration.defined_enums[config_name][value]
          ActiveRecord::Base.connected_to(role: :writing) do
            config.update!(config_name => value)
          end
        end
      end
    end
  end
end
