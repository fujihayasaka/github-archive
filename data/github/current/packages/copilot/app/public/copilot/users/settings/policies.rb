# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Settings
      module Policies
        extend T::Helpers
        include Copilot::Users::Signatures

        abstract!

        include HasConfiguration

        ######   BASIC POLICIES   ######

        delegate :desktop_no_policy?, :desktop_unconfigured?,
                 :dotcom_chat_no_policy?, :dotcom_chat_unconfigured?,
                 to: :configuration

        # bing_github_chat methods
        sig { returns(String) }
        def bing_github_chat
          if bing_github_chat_enabled?
            "enabled"
          elsif bing_github_chat_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end

        sig { void }
        def bing_github_chat_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.bing_github_chat_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.bing_github_chat_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def bing_github_chat_disabled?
          !bing_github_chat_enabled?
        end

        sig { void }
        def bing_github_chat_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.bing_github_chat_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.bing_github_chat_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def bing_github_chat_enabled?
          if copilot_plan_individual?
            return ActiveRecord::Base.connected_to(role: :reading) do
              configuration.bing_github_chat_enabled?
            end
          end

          # Standalone businesses can also provide this policy to users.
          if copilot_businesses.size > 0
            return false if copilot_businesses.any?(&:bing_github_chat_disabled?)
            return true if copilot_businesses.all?(&:bing_github_chat_enabled?)
            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:bing_github_chat)
          end

          return false if copilot_organizations.empty?
          copilot_organizations.any? { |org| org.bing_github_chat_enabled? }
        end

        # desktop methods
        sig { override.returns(String) }
        def desktop
          if desktop_enabled?
            "enabled"
          elsif desktop_disabled?
            "disabled"
          else
            "unconfigured"
          end
        end
        sig { override.returns(T::Boolean) }
        def desktop_configured?
          return true if copilot_organizations.any?(&:desktop_configured?)

          ActiveRecord::Base.connected_to(role: :reading) do
            !configuration.desktop_unconfigured?
          end
        end

        sig { override.void }
        def desktop_disabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.desktop_disabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.desktop_disabled",
            tags: ["type:user"],
          )
        end


        sig { override.returns(T::Boolean) }
        def desktop_disabled?
          return true unless user_object.feature_flag_enabled_or_raise?(:copilot_desktop) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

          return true if has_limited_access? && !user_object.feature_flag_enabled_or_raise?(:copilot_free_desktop) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          return false if has_cfi_access?

          # If any non-business in which the user has a Copilot seat has disabled this
          # feature, it is disabled for the user.
          return true if copilot_businesses.any?(&:desktop_disabled?)

          return false if copilot_organizations.any?(&:desktop_enabled?)
          return true if copilot_organizations.any? && copilot_organizations.all?(&:desktop_disabled?)

          configuration.desktop_disabled?
        end

        sig { override.void }
        def desktop_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.desktop_enabled!
          end

          GitHub.dogstats.increment(
            "copilot.settings.desktop_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def desktop_enabled?
          return false unless user_object.feature_flag_enabled_or_raise?(:copilot_desktop) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

          return false if has_limited_access? && !user_object.feature_flag_enabled_or_raise?(:copilot_free_desktop) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          return true if has_cfi_access?

          return false if copilot_businesses.any?(&:desktop_disabled?)
          return true if copilot_businesses.all?(&:desktop_enabled?) unless copilot_businesses.empty?

          return true if copilot_organizations.any?(&:desktop_enabled?)
          return false if copilot_organizations.any? && copilot_organizations.all?(&:desktop_disabled?)

          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:desktop)

          false
        end

        sig { override.void }
        def desktop_no_policy!
          # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.desktop_no_policy",
            tags: ["type:user"],
          )
        end

        # dotcom_chat methods
        sig { override.returns(String) }
        def dotcom_chat
          return "enabled" if dotcom_chat_enabled?
          return "disabled" if dotcom_chat_disabled?
          "unconfigured"
        end

        sig { override.returns(T::Boolean) }
        def dotcom_chat_configured?
          return true if copilot_organizations.any?(&:dotcom_chat_configured?)

          ActiveRecord::Base.connected_to(role: :reading) do
            !configuration.dotcom_chat_unconfigured?
          end
        end

        sig { override.void }
        def disable_dotcom_chat!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.update!(dotcom_chat: :disabled)
          end

          GitHub.dogstats.increment(
            "copilot.settings.dotcom_chat_disabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def dotcom_chat_disabled?
          # Todo: uncomment after updating default config value to unconfigured.
          # return true if configuration.dotcom_chat_disabled?

          return true if copilot_businesses.any?(&:dotcom_chat_disabled?)

          return false if copilot_organizations.any?(&:dotcom_chat_enabled?)

          return true if copilot_organizations.any? && copilot_organizations.all?(&:dotcom_chat_disabled?)

          # Todo: remove after updating default config value to unconfigured.
          configuration.dotcom_chat_disabled?
        end

        sig { override.void }
        def dotcom_chat_enabled!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.update!(dotcom_chat: :enabled)
          end

          GitHub.dogstats.increment(
            "copilot.settings.dotcom_chat_enabled",
            tags: ["type:user"],
          )
        end

        sig { override.returns(T::Boolean) }
        def dotcom_chat_enabled?
          GitHub.tracer.in_span("copilot_user.dotcom_chat_enabled?") do |_span|
            # Todo: uncomment after updating default config value to unconfigured.
            # return false if configuration.dotcom_chat_disabled?
            return false if copilot_businesses.any?(&:dotcom_chat_disabled?)
            return true if copilot_businesses.all?(&:dotcom_chat_enabled?) unless copilot_businesses.empty?

            return true if copilot_organizations.any?(&:dotcom_chat_enabled?)

            return false if copilot_organizations.any? && copilot_organizations.all?(&:dotcom_chat_disabled?)

            return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:dotcom_chat)

            # if they have CI then dotcom chat is always enabled
            # otherwise we fall through to their cached settings
            return true if has_ci_access?

            configuration.dotcom_chat_enabled?
          end
        end

        sig { override.void }
        def dotcom_chat_no_policy!
          # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

          GitHub.dogstats.increment(
            "copilot.settings.copilot_for_dotcom_no_policy",
            tags: ["type:user"],
          )
        end

        sig { returns(T::Boolean) }
        def unconfigured_dotcom_chat?
          configuration.dotcom_chat_unconfigured?
        end

        # public code suggestions methods
        sig { override.returns(String) }
        def snippy_setting
          return "enabled" if block_public_code_suggestions?
          return "disabled" if allow_public_code_suggestions?
          "unconfigured"
        end

        # This disables snippy
        sig { override.void }
        def allow_public_code_suggestions!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.update!(public_code_suggestions: :allowed)
          end

          GitHub.dogstats.increment(
            "copilot.settings.public_code_suggestions_allowed",
            tags: ["type:user"],
          )
        end

        # Returns the effective allow setting for snippy. The user can configure
        # this for Copilot, or it can be inherited from an Organization or
        # Business via seats.
        sig { override.returns(T::Boolean) }
        def allow_public_code_suggestions?
          return false if copilot_organizations.any?(&:block_public_code_suggestions?)
          return true if copilot_organizations.any?(&:allow_public_code_suggestions?)

          return false if copilot_businesses.any?(&:block_public_code_suggestions?)
          return true if copilot_businesses.any?(&:allow_public_code_suggestions?)

          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:public_code_suggestions)

          # snippy is disabled
          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_allowed? || configuration.public_code_suggestions_unconfigured?
          end
        end

        # This enables snippy
        sig { override.void }
        def block_public_code_suggestions!
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.public_code_suggestions_blocked!
          end

          GitHub.dogstats.increment(
            "copilot.settings.public_code_suggestions_blocked",
            tags: ["type:user"],
          )
        end

        # Returns the effective block setting for snippy. The user can configure
        # this for Copilot, or it can be inherited from an Organization or
        # Business via seats.  This policy is MOST RESTRICITVE, meaning if any of the user's orgs or businesses block
        # public code suggestions, the user's setting is blocked.
        sig { override.returns(T::Boolean) }
        def block_public_code_suggestions?
          return true if copilot_organizations
            .any?(&:block_public_code_suggestions?)
          return true if copilot_businesses
            .any?(&:block_public_code_suggestions?)

          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:public_code_suggestions)

          return false if copilot_organizations.present? && copilot_organizations
            .all?(&:allow_public_code_suggestions?)
          return false if copilot_businesses.present? && copilot_businesses
            .all?(&:allow_public_code_suggestions?)

          ActiveRecord::Base.connected_to(role: :reading) do
            configuration.public_code_suggestions_blocked?
          end
        end


        # So, funny story. Snippy is the name of a tool that is used to redact code suggestions from public sources
        # It can be ENABLED or DISABLED.
        # In the UI, we use the terms ALLOW/BLOCK and make the mistake of thinking those mapped to
        # ENABLED and DISABLED respectively.
        #
        # They didn't - they map to the inverse.
        #
        # If you want to ALLOW public code suggestions, you need to DISABLE snippy.
        # If you want to BLOCK public code suggestions, you need to ENABLE snippy.
        sig { override.returns(T::Boolean) }
        def public_code_suggestions_configured?
          true
        end

        ###### END BASIC POLICIES ######

        private

        # If the user has an enterprise-assigned Copilot seat we check if the policy is set to `no_policy` and if so
        # determine if this policy is enabled for the user based on the fallback policy setting.
        sig { params(policy: Symbol).returns(T::Boolean) }
        def business_copilot_provider_ea_user_fallback_policy_enabled?(policy)
          return false unless copilot_businesses.any?

          # Find the business that is providing the current seat and check it's policy settings
          copilot_provider = self.copilot_provider
          copilot_obj = copilot_provider&.__getobj__
          return false unless copilot_obj.is_a?(::Business) && !copilot_provider&.copilot_standalone? && copilot_obj.feature_flag_enabled_or_raise?(:copilot_business_user_assignment) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

          copilot_provider = T.cast(copilot_provider, Copilot::Business)

          return true if T.unsafe(copilot_provider)&.send(policy) == "no_policy" && copilot_provider.ea_user_fallback_policy_enabled?

          false
        end
      end
    end
  end
end
