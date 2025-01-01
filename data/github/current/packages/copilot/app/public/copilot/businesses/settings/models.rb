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

        delegate :a_chat, :a_chat_unconfigured?, :a_chat_configured?, :a_chat_enabled?, :a_chat_disabled?, :a_chat_no_policy?,
                 :g_chat, :g_chat_unconfigured?, :g_chat_configured?, :g_chat_enabled?, :g_chat_disabled?, :g_chat_no_policy?,
                 :gtff, :gtff_unconfigured?, :gtff_enabled?, :gtff_disabled?, :gtff_no_policy?,
                 :o3, :o3_unconfigured?, :o3_configured?, :o3_enabled?, :o3_disabled?, :o3_no_policy?,
                 :obmb, :obmb_unconfigured?, :obmb_enabled?, :obmb_disabled?, :obmb_no_policy?,
                 :obmw, :obmw_unconfigured?, :obmw_enabled?, :obmw_disabled?, :obmw_no_policy?,
                 :ofct, :ofct_unconfigured?, :ofct_enabled?, :ofct_disabled?, :ofct_no_policy?,
                 :aofo, :aofo_unconfigured?, :aofo_enabled?, :aofo_disabled?, :aofo_no_policy?,
                 :ofo, :ofo_unconfigured?, :ofo_enabled?, :ofo_disabled?, :ofo_no_policy?,
                 :grok_code, :grok_code_unconfigured?, :grok_code_enabled?, :grok_code_disabled?, :grok_code_no_policy?,
                 to: :configuration

        # a_chat methods
        sig { override.void }
        def a_chat_enabled!
          update_configuration!("a_chat", "enabled", send_email: true)
        end

        sig { override.void }
        def a_chat_disabled!
          update_configuration!("a_chat", "disabled", send_email: true)
        end

        sig { override.void }
        def a_chat_no_policy!
          update_configuration!("a_chat", "no_policy", send_email: false)
        end

        # g_chat methods
        sig { override.void }
        def g_chat_enabled!
          update_configuration!("g_chat", "enabled", send_email: true)
        end

        sig { override.void }
        def g_chat_disabled!
          update_configuration!("g_chat", "disabled", send_email: true)
        end

        sig { override.void }
        def g_chat_no_policy!
          update_configuration!("g_chat", "no_policy", send_email: false)
        end

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

        ###### END BASIC MODELS ######
      end
    end
  end
end
