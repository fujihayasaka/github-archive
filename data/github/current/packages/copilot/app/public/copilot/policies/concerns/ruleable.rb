# typed: strict
# frozen_string_literal: true

# The Rulable module is a marker concern to indicate that a policy supports setting rules.

module Copilot
  module Policies
    module Concerns
      module Ruleable
        extend T::Helpers
        include Copilot::Policy

        abstract!

        # value of the policy from the configuration model including any rules if the FF is on
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(String) }
        def value(entity)
          # CFI users don't use setting rules
          return configuration_value(entity) if entity.sorbet_class == ::User && T.cast(entity, Copilot::User).has_cfi_access?

          if entity.feature_flag_enabled_include_parents?(:use_setting_rules_copilot_models, default: false) && setting_rules_supported_policy?
            result = CopilotDomain.domain.settings.get_effective_value(entity, Copilot::Settings::CopilotModelSetting,
              setting_name: "copilot.models.supported_models.#{config_name}")
            result.serialize
          else
            configuration_value(entity)
          end
        end

        sig { override.returns(T::Boolean) }
        def setting_rules_supported_policy?
          CopilotDomain.domain.settings.definition_by_name("copilot.models.supported_models.#{config_name}").present?
        end

        sig { params(org: Copilot::Organization).returns(T::Boolean) }
        def rules_disables_propagation?(org)
          # Propogate updates unless setting rules are enabled
          setting_rules_supported_policy? && org.feature_flag_enabled_include_parents?(:use_setting_rules_copilot_models, default: false)
        end
      end
    end
  end
end
