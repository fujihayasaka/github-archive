# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Settings
      module Models
        extend T::Helpers
        include Copilot::Businesses::Signatures

        abstract!

        include HasConfiguration

        ######   BASIC MODELS   ######

        delegate :gtff, :gtff_unconfigured?, :gtff_enabled?, :gtff_disabled?, :gtff_no_policy?,
                 :o3, :o3_unconfigured?, :o3_configured?, :o3_enabled?, :o3_disabled?, :o3_no_policy?,
                 :obmb, :obmb_unconfigured?, :obmb_enabled?, :obmb_disabled?, :obmb_no_policy?,
                 :obmw, :obmw_unconfigured?, :obmw_enabled?, :obmw_disabled?, :obmw_no_policy?,
                 :ofct, :ofct_unconfigured?, :ofct_enabled?, :ofct_disabled?, :ofct_no_policy?,
                 :aofo, :aofo_unconfigured?, :aofo_enabled?, :aofo_disabled?, :aofo_no_policy?,
                 :ofo, :ofo_unconfigured?, :ofo_enabled?, :ofo_disabled?, :ofo_no_policy?,
                 :daisy, # Still needed for business_copilot_provider_ea_user_fallback_policy. Refactored code for the rest
                 :grok_code, :grok_code_unconfigured?, :grok_code_enabled?, :grok_code_disabled?, :grok_code_no_policy?,
                 :m_ironman, :m_ironman_unconfigured?, :m_ironman_enabled?, :m_ironman_disabled?, :m_ironman_no_policy?,
                 :m_spiderman, :m_spiderman_unconfigured?, :m_spiderman_enabled?, :m_spiderman_disabled?, :m_spiderman_no_policy?,
                 :m_thor, :m_thor_unconfigured?, :m_thor_enabled?, :m_thor_disabled?, :m_thor_no_policy?,
                 to: :configuration

        # gtff methods
        sig { override.void }
        def gtff_enabled!
          update_configuration!("gtff", "enabled", send_email: false)
        end

        sig { override.void }
        def gtff_disabled!
          update_configuration!("gtff", "disabled", send_email: false)
        end

        sig { override.void }
        def gtff_no_policy!
          update_configuration!("gtff", "no_policy", send_email: false)
        end

        # o3 methods
        sig { override.void }
        def o3_enabled!
          update_configuration!("o3", "enabled", send_email: true)
        end

        sig { override.void }
        def o3_disabled!
          update_configuration!("o3", "disabled", send_email: true)
        end

        sig { override.void }
        def o3_no_policy!
          update_configuration!("o3", "no_policy", send_email: false)
        end

        # obmb methods

        sig { override.void }
        def obmb_enabled!
          update_configuration!("obmb", "enabled", send_email: false)
        end

        sig { override.void }
        def obmb_disabled!
          update_configuration!("obmb", "disabled", send_email: false)
        end

        sig { override.void }
        def obmb_no_policy!
          update_configuration!("obmb", "no_policy", send_email: false)
        end

        # obmw methods

        sig { override.void }
        def obmw_enabled!
          update_configuration!("obmw", "enabled", send_email: false)
        end

        sig { override.void }
        def obmw_disabled!
          update_configuration!("obmw", "disabled", send_email: false)
        end

        sig { override.void }
        def obmw_no_policy!
          update_configuration!("obmw", "no_policy", send_email: false)
        end

        # ofct methods

        sig { override.void }
        def ofct_enabled!
          update_configuration!("ofct", "enabled", send_email: false)
        end

        sig { override.void }
        def ofct_disabled!
          update_configuration!("ofct", "disabled", send_email: false)
        end

        sig { override.void }
        def ofct_no_policy!
          update_configuration!("ofct", "no_policy", send_email: false)
        end

        # aofo methods

        sig { override.void }
        def aofo_enabled!
          update_configuration!("aofo", "enabled", send_email: false)
        end

        sig { override.void }
        def aofo_disabled!
          update_configuration!("aofo", "disabled", send_email: false)
        end

        sig { override.void }
        def aofo_no_policy!
          update_configuration!("aofo", "no_policy", send_email: false)
        end

        # ofo methods
        sig { override.void }
        def ofo_enabled!
          update_configuration!("ofo", "enabled", send_email: false)
        end

        sig { override.void }
        def ofo_disabled!
          update_configuration!("ofo", "disabled", send_email: false)
        end

        sig { override.void }
        def ofo_no_policy!
          update_configuration!("ofo", "no_policy", send_email: false)
        end

        # grok methods

        sig { override.void }
        def grok_code_enabled!
          update_configuration!("grok_code", "enabled", send_email: false)
        end

        sig { override.void }
        def grok_code_disabled!
          update_configuration!("grok_code", "disabled", send_email: false)
        end

        sig { override.void }
        def grok_code_no_policy!
          update_configuration!("grok_code", "no_policy", send_email: false)
        end

        # m_ironman methods

        sig { override.void }
        def m_ironman_enabled!
          update_configuration!("m_ironman", "enabled", send_email: false)
        end

        sig { override.void }
        def m_ironman_disabled!
          update_configuration!("m_ironman", "disabled", send_email: false)
        end

        sig { override.void }
        def m_ironman_no_policy!
          update_configuration!("m_ironman", "no_policy", send_email: false)
        end

        # m_spiderman methods

        sig { override.void }
        def m_spiderman_enabled!
          update_configuration!("m_spiderman", "enabled", send_email: false)
        end

        sig { override.void }
        def m_spiderman_disabled!
          update_configuration!("m_spiderman", "disabled", send_email: false)
        end

        sig { override.void }
        def m_spiderman_no_policy!
          update_configuration!("m_spiderman", "no_policy", send_email: false)
        end

        # m_thor methods

        sig { override.void }
        def m_thor_enabled!
          update_configuration!("m_thor", "enabled", send_email: false)
        end

        sig { override.void }
        def m_thor_disabled!
          update_configuration!("m_thor", "disabled", send_email: false)
        end

        sig { override.void }
        def m_thor_no_policy!
          update_configuration!("m_thor", "no_policy", send_email: false)
        end

        ###### END BASIC MODELS ######

        sig { params(model_key: String).returns(T::Boolean) }
        def model_enabled?(model_key)
          model_policy(model_key) == "enabled"
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_disabled?(model_key)
          model_policy(model_key) == "disabled"
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_no_policy?(model_key)
          model_policy(model_key) == "no_policy"
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_unconfigured?(model_key)
          model_policy(model_key) == "unconfigured"
        end

        sig { params(model_key: String).void }
        def model_enabled!(model_key)
          update_model_configuration!(model_key, "enabled")
        end

        sig { params(model_key: String).void }
        def model_disabled!(model_key)
          update_model_configuration!(model_key, "disabled")
        end

        sig { params(model_key: String).void }
        def model_no_policy!(model_key)
          update_model_configuration!(model_key, "no_policy")
        end

        sig { params(model_key: String).returns(String) }
        def model_policy(model_key)
          business = Copilot::Business.new(business_object)
          models = Copilot::ModelsRegistryCache.for_enterprise(business)
          model = models.find { |m| m.model_key == model_key }

          return "unconfigured" unless model.present?

          configuration.model_policy(model_key)
        end

        private

        sig { params(model_key: String, value: String).void }
        def update_model_configuration!(model_key, value)
          return unless %w[enabled disabled no_policy].include?(value)
          business = Copilot::Business.new(business_object)
          return if value == "no_policy" && business.is_standalone_business?

          models = Copilot::ModelsRegistryCache.for_enterprise(business)
          model = models.find { |m| m.model_key == model_key }
          return unless model.present?

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.set_model_policy(model_key, value)
          end

          GitHub.dogstats.increment(
            "copilot.settings.#{model_key}_#{value}",
            tags: ["type:business"],
          )

          propagate_organization_settings!
        end
      end
    end
  end
end
