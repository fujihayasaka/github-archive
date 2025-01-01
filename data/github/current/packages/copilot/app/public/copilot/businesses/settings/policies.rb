# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Settings
      module Policies
        extend T::Helpers
        include Copilot::Helpers
        include Copilot::Businesses::Licensing
        include Copilot::Businesses::Signatures
        include Copilot::Businesses::Trials

        abstract!

        include HasConfiguration

        ######   BASIC POLICIES   ######

        delegate :bing_github_chat, :bing_github_chat_disabled?, :bing_github_chat_enabled?, :chat_enabled,
                 :dotcom_chat, :dotcom_chat_unconfigured?, :dotcom_chat_configured?, :dotcom_chat_enabled?,
                 :dotcom_chat_disabled?, :dotcom_chat_no_policy?, :dotcom_chat_chat_enabled?,
                 :desktop, :desktop_unconfigured?, :desktop_configured?, :desktop_enabled?, :desktop_disabled?, :desktop_no_policy?,
                 to: :configuration


        # bing_github_chat methods
        sig { override.void }
        def bing_github_chat_disabled!
          update_configuration!("bing_github_chat", "disabled", send_email: true)
        end

        sig { override.void }
        def bing_github_chat_enabled!
          update_configuration!("bing_github_chat", "enabled", send_email: true)
        end

        sig { override.returns(T::Boolean) }
        def bing_github_chat_no_policy?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.bing_github_chat_no_policy?
          end
        end

        sig { override.void }
        def bing_github_chat_no_policy!
          update_configuration!("bing_github_chat", "no_policy", send_email: false)
        end

        # dotcom_chat methods
        sig { override.void }
        def dotcom_chat_enabled!
          update_configuration!("dotcom_chat", "enabled", send_email: true)
        end

        sig { override.void }
        def disable_dotcom_chat!
          update_configuration!("dotcom_chat", "disabled", send_email: true)
        end

        sig { override.void }
        def dotcom_chat_no_policy!
          update_configuration!("dotcom_chat", "no_policy", send_email: false)
        end

        # desktop methods
        sig { override.void }
        def desktop_enabled!
          update_configuration!("desktop", "enabled")
        end

        sig { override.void }
        def desktop_no_policy!
          update_configuration!("desktop", "no_policy", send_email: false)
        end

        sig { override.void }
        def desktop_disabled!
          update_configuration!("desktop", "disabled")
        end

        # public_code_suggestions methods
        sig { override.returns(T::Boolean) }
        def allow_public_code_suggestions?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_allowed?
          end
        end

        # Allows public code suggestions for this business and all of its
        # organizations.
        sig { override.void }
        def allow_public_code_suggestions!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.update!(public_code_suggestions: :allowed)
          end

          propagate_organization_settings!

          GitHub.dogstats.increment(
            "copilot.settings.public_code_suggestions_allowed",
            tags: ["type:business"]
          )
        end

        sig { override.returns(T::Boolean) }
        def block_public_code_suggestions?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_blocked?
          end
        end

        # Blocks public code suggestions for this business and all of its
        # organizations.
        sig { override.void }
        def block_public_code_suggestions!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.public_code_suggestions_blocked!
          end

          propagate_organization_settings!

          GitHub.dogstats.increment(
            "copilot.settings.public_code_suggestions_blocked",
            tags: ["type:business"],
          )
        end

        sig { override.returns(T::Boolean) }
        def no_public_code_suggestions_policy?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_no_policy?
          end
        end

        # Sets no public code suggestions policy for this business. Does not
        # modify child organizations.
        sig { override.void }
        def no_public_code_suggestions_policy!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.public_code_suggestions_no_policy!
          end
        end

        sig { override.returns(T::Boolean) }
        def public_code_suggestions_configured?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_configured?
          end
        end

        sig { override.returns(String) }
        def snippy_setting
          ActiveRecord::Base.connected_to(role: :reading) do
            case configuration.public_code_suggestions
            when "allowed" then "disabled"
            when "blocked" then "enabled"
            when "no_policy" then "no_policy"
            end
          end
        end

        ###### END BASIC POLICIES ######
      end
    end
  end
end
