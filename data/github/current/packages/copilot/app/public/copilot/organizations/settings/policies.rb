# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Settings
      module Policies
        extend T::Helpers
        include Copilot::Organizations::Signatures

        abstract!

        include HasConfiguration

        ######   BASIC POLICIES   ######

        delegate :bing_github_chat,
                 :desktop, :desktop_unconfigured?, :desktop_configured?, :desktop_enabled?, :desktop_disabled?, :desktop_no_policy?,
                 :dotcom_chat, :dotcom_chat_unconfigured?, :dotcom_chat_configured?, :dotcom_chat_enabled?,
                 :dotcom_chat_disabled?, :dotcom_chat_no_policy?, :dotcom_chat_chat_enabled?,
                 to: :configuration


        # bing_github_chat methods
        sig { override.returns(T::Boolean) }
        def bing_github_chat_disabled?
          !bing_github_chat_enabled?
        end

        sig { override.params(force: T::Boolean).void }
        def bing_github_chat_disabled!(force: false)
          # Bing can only be toggled at the org level if there is no business policy
          return if bing_github_chat_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.bing_github_chat_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.bing_github_chat_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.returns(T::Boolean) }
        def bing_github_chat_enabled?
          # use the business policy for Bing if it exists, otherwise use the org setting
          if bing_github_chat_policy_inherited?
            T.must(copilot_business).bing_github_chat_enabled?
          else
            configuration.bing_github_chat_enabled?
          end
        end

        sig { override.params(force: T::Boolean).void }
        def bing_github_chat_enabled!(force: false)
          # Bing can only be toggled at the org level if there is no business policy
          return if bing_github_chat_policy_inherited? && !force

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.bing_github_chat_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.bing_github_chat_enabled",
            tags: ["type:organization"],
          )
        end

        sig { returns(T::Boolean) }
        def bing_github_chat_policy_inherited?
          return false unless copilot_business
          !T.must(copilot_business).bing_github_chat_no_policy?
        end

        # desktop methods
        sig { override.params(send_email: T::Boolean).void }
        def desktop_disabled!(send_email = true)
          previously_enabled = desktop_enabled?

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.desktop_disabled!
          end

          # We are not sending emails unless the organization has previously enabled desktop, even if the call-site
          # passes in send_email = true. We will still honor the send_email param but only if the organization was
          # enabled
          # See: https://github.com/github/heart-services/issues/5836
          if send_email && previously_enabled
            Copilot::Seat.for_organization(organization_object).each do |seat|
              CopilotForBusinessMailer.desktop_disabled_for_user(organization_object, seat.assigned_user).deliver_later
            end
          end

          GitHub.dogstats.increment(
            "copilot.settings.desktop_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.params(send_email: T::Boolean).void }
        def desktop_enabled!(send_email = true)
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.desktop_enabled!
          end

          if send_email
            Copilot::Seat.for_organization(organization_object).each do |seat|
              CopilotForBusinessMailer.desktop_enabled_for_user(organization_object, seat.assigned_user).deliver_later
            end
          end

          GitHub.dogstats.increment(
            "copilot.settings.desktop_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def desktop_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.desktop_no_policy",
            tags: ["type:organization"],
          )
        end

        # dotcom_chat methods
        sig { override.void }
        def disable_dotcom_chat!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.update!(dotcom_chat: :disabled)
          end

          GitHub.dogstats.increment(
            "copilot.settings.dotcom_chat_disabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def dotcom_chat_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.dotcom_chat_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.dotcom_chat_enabled",
            tags: ["type:organization"],
          )
        end

        sig { override.void }
        def dotcom_chat_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.dotcom_chat_no_policy",
            tags: ["type:organization"],
          )
        end

        # public code suggestions methods
        sig { override.void }
        def allow_public_code_suggestions!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.update!(public_code_suggestions: :allowed)
          end

          GitHub.dogstats.increment(
            "copilot.settings.public_code_suggestions_allowed",
            tags: ["type:organization"],
          )
        end

        sig { override.returns(T::Boolean) }
        def allow_public_code_suggestions?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_allowed?
          end
        end

        sig { override.void }
        def block_public_code_suggestions!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.public_code_suggestions_blocked!
          end

          GitHub.dogstats.increment(
            "copilot.settings.public_code_suggestions_blocked",
            tags: ["type:organization"],
          )
        end

        sig { override.returns(T::Boolean) }
        def block_public_code_suggestions?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_blocked?
          end
        end

        sig { override.returns(T::Boolean) }
        def no_public_code_suggestions_policy?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_no_policy?
          end
        end

        sig { override.returns(T::Boolean) }
        def public_code_suggestions_configured?
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_configured?
          end
        end

        sig { override.returns([Integer, Integer]) }
        def public_code_suggestions_sorting
          sorting = ActiveRecord::Base.connected_to(role: :reading) do
            case configuration.public_code_suggestions
            when "blocked" then 0
            when "allowed" then 1
            else 2
            end
          end

          [sorting, organization_object.id]
        end

        sig { override.returns(String) }
        def snippy_setting
          ActiveRecord::Base.connected_to(role: :reading) do
            case configuration.public_code_suggestions
            when "allowed" then "disabled"
            when "blocked" then "enabled"
            else "unconfigured"
            end
          end
        end

        ###### END BASIC POLICIES ######
      end
    end
  end
end
