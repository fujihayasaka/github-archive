# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Settings
      extend T::Helpers
      include Copilot::Helpers
      include Copilot::Organizations::Signatures
      include Copilot::Organizations::FeatureEnabled
      include GitHub::Memoizer

      abstract!

      include HasConfiguration

      delegate :copilot_for_dotcom, :copilot_for_dotcom_unconfigured?, :copilot_for_dotcom_configured?, :copilot_for_dotcom_enabled?,
               :copilot_for_dotcom_disabled?, :copilot_for_dotcom_no_policy?, :copilot_for_dotcom_chat_enabled?, :copilot_for_dotcom_setting,
               :dotcom_chat, :dotcom_chat_unconfigured?, :dotcom_chat_configured?, :dotcom_chat_enabled?,
               :dotcom_chat_disabled?, :dotcom_chat_no_policy?, :dotcom_chat_chat_enabled?, :mobile_chat, :mobile_chat_no_policy?,
               :custom_models, :custom_models_unconfigured?, :custom_models_configured?, :custom_models_enabled?,
               :custom_models_disabled?, :custom_models_no_policy?, :custom_models_chat_enabled?,
               :cli, :cli_unconfigured?, :cli_configured?, :cli_enabled?,
               :cli_disabled?, :cli_no_policy?, :cli_chat_enabled?,
               :private_docs, :private_docs_unconfigured?, :private_docs_configured?, :private_docs_enabled?,
               :private_docs_disabled?, :private_docs_no_policy?, :private_docs_chat_enabled?,
               :pr_summarizations, :pr_summarizations_unconfigured?, :pr_summarizations_configured?, :pr_summarizations_enabled?,
               :pr_summarizations_disabled?, :pr_summarizations_no_policy?, :pr_summarizations_chat_enabled?,
               :usage_telemetry_api,
               :copilot_plan_unconfigured?,
               :pending_plan_downgrade_date, :copilot_extensions, :copilot_extensions_unconfigured?, :copilot_extensions_configured?,
               :copilot_extensions_enabled?, :copilot_extensions_disabled?, :copilot_extensions_no_policy?,
               :private_telemetry, :private_telemetry_unconfigured?, :private_telemetry_configured?,
               :private_telemetry_enabled?, :private_telemetry_disabled?, :private_telemetry_no_policy?,
               :a_chat, :a_chat_unconfigured?, :a_chat_configured?, :a_chat_enabled?,
               :a_chat_disabled?, :a_chat_no_policy?,
               :g_chat, :g_chat_unconfigured?, :g_chat_configured?, :g_chat_enabled?,
               :g_chat_disabled?, :g_chat_no_policy?,
               :o1, :o1_unconfigured?, :o1_configured?, :o1_enabled?,
               :o1_disabled?, :o1_no_policy?,
               to: :configuration

      alias dotcom_chat_setting dotcom_chat
      alias custom_models_setting custom_models
      alias cli_setting cli
      alias a_chat_setting a_chat
      alias g_chat_setting g_chat
      alias o1_setting o1
      alias private_docs_setting private_docs
      alias pr_summarizations_setting pr_summarizations
      alias usage_telemetry_api_setting usage_telemetry_api
      alias mobile_chat_setting mobile_chat
      alias copilot_extensions_setting copilot_extensions
      alias private_telemetry_setting private_telemetry

      sig { override.returns(T.nilable(::Customer)) }
      def customer
        organization_object.customer
      end

      sig { override.returns(T::Boolean) }
      def show_csv_exports?
        organization_object.feature_enabled?(:copilot_show_csv_exports)
      end

      sig { override.void }
      def telemetry_aggregation_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.usage_telemetry_api_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.usage_telemetry_api_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def telemetry_aggregation_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.usage_telemetry_api_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.usage_telemetry_api_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def telemetry_aggregation_enabled?
        # check whether the business has explicitly enabled or disabled (if applicable)
        if copilot_business
          case T.must(copilot_business).usage_telemetry_api_setting
          when "enabled"
            return true
          when "disabled"
            return false
          end
        end

        # otherwise, the org admin has to CHOOSE to enable it
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.usage_telemetry_api_enabled?
        end
      end

      sig { returns(T::Boolean) }
      def telemetry_aggregation_disabled?
        # if the business has blocked it, this feature is considered disabled
        return true if copilot_business && T.must(copilot_business).telemetry_aggregation_disabled?

        # otherwise, the org admin has to CHOOSE to enable it
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.usage_telemetry_api_disabled?
        end
      end

      # whether the organization has been feature flagged to not be charged
      sig { override.returns(T::Boolean) }
      def copilot_for_business_free?
        return true if organization_object.feature_enabled?(:copilot_for_business_free)
        return true if organization_object.business.present? && organization_object.business&.feature_enabled?(:copilot_for_business_free)
        false
      end

      # An org admin can modify their enabled setting if:
      # - if the enterprise is enabled for all orgs
      # - if the enterprise is enabled for selected orgs and this org is not
      #   disabled
      # - if there is no parent enterprise and this org is enabled
      sig { override.returns(T::Boolean) }
      def has_copilot_for_business?
        return copilot_enabled? unless copilot_business

        b = T.must(copilot_business)
        case
        when b.copilot_enabled_for_all_organizations?
          true
        when b.copilot_enabled_for_selected_organizations?
          copilot_enabled?
        when b.copilot_disabled?
          false
        else
          false
        end
      end

      sig { returns(T::Boolean) }
      def is_available_for_copilot_signup?
        return false if copilot_enabled?
        return false if copilot_business

        GitHub.copilot_for_individuals_enabled?
      end

      # For orgs that are part of an enterprise we always return true
      # For standalone orgs, we check the copilot_enabled? setting
      sig { override.returns(T::Boolean) }
      def copilot_for_business_enabled?
        copilot_business.present? || copilot_enabled?
      end

      sig { returns(T::Boolean) }
      def is_business_in_trial_period?
        return false unless GitHub.copilot_for_business_enabled?

        !!copilot_business&.business_object&.trial?
      end

      sig { returns(T::Boolean) }
      def can_upgrade_trial?
        if organization_object.business
          return false if is_business_in_trial_period?
          return !!copilot_business&.copilot_billable?
        end

        true
      end

      sig { override.returns(T::Boolean) }
      def copilot_disabled?
        return true if copilot_business&.copilot_disabled?

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.disabled?
        end
      end

      sig { override.params(actor: T.nilable(::User)).void }
      def disable_copilot!(actor = nil)
        old_settings = copilot_organization_settings

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.disabled!
        end

        new_settings = copilot_organization_settings

        unless old_settings == new_settings
          Copilot::Instrumenter.instrument_organization_settings_changed(
              organization_object,
              actor,
              old_settings: old_settings,
              new_settings: new_settings,
          ) if actor
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_enabled?
        if copilot_business
          cb = T.must(copilot_business)

          # if the business is set to enabled for selected, we fall through to checking the configuration for this organization
          # otherwise, we're checking the setting for the business
          return true if cb.copilot_enabled_for_all_organizations?
          return false unless cb.copilot_enabled?
        end

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.enabled?
        end
      end

      sig { override.returns(String) }
      def copilot_enablement_setting
        if business_trial
          trial_name = T.must(business_trial).display_name
          return "#{trial_name} Extended" if T.must(business_trial).extended?
          return "#{trial_name} Active" if T.must(business_trial).active?
          return "#{trial_name} Pending" if T.must(business_trial).pending?
        end

        if copilot_business
          cb = T.must(copilot_business)
          return "Enabled By Enterprise Admin (All Orgs)" if cb.copilot_enabled_for_all_organizations?

          if cb.copilot_enabled_for_selected_organizations?
            return "Enabled By Enterprise Admin" if copilot_enabled?
            return "Not Enabled for This Organization By Enterprise Admin" if copilot_disabled?
          end
          return "Disabled By Enterprise Admin" if cb.copilot_disabled?
        end

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.enabled? ? "Enabled by Organization Admin" : "Not Enabled by Organization Admin"
        end
      end

      sig { override.params(actor: T.nilable(::User)).void }
      def enable_copilot!(actor = nil)
        old_settings = copilot_organization_settings

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.enabled!
        end

        new_settings = copilot_organization_settings

        unless old_settings == new_settings
          Copilot::Instrumenter.instrument_organization_settings_changed(
            organization_object,
            actor,
            old_settings: old_settings,
            new_settings: new_settings,
          ) if actor
        end
      end

      sig { override.returns(T::Boolean) }
      def public_code_suggestions_configured?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_configured?
        end
      end

      sig { override.returns(T::Boolean) }
      def no_public_code_suggestions_policy?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_no_policy?
        end
      end

      sig { override.returns(T::Boolean) }
      def chat_enabled_configured?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled_configured?
        end
      end

      sig { override.returns(String) }
      def copilot_chat_setting
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled
        end
      end

      sig { override.returns(T::Boolean) }
      def chat_enabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled_enabled?
        end
      end

      sig { override.params(send_email: T::Boolean).void }
      def enable_chat!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(chat_enabled: :enabled)
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotForBusinessMailer.chat_enabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.chat_enabled_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def mobile_chat_enabled?
        return T.must(copilot_business).mobile_chat_enabled? if mobile_chat_policy_inherited?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.mobile_chat_enabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def mobile_chat_disabled?
        return T.must(copilot_business).mobile_chat_disabled? if mobile_chat_policy_inherited?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.mobile_chat_disabled?
        end
      end

      sig { returns(T::Boolean) }
      def mobile_chat_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).no_mobile_chat_policy?
      end

      sig { override.params(send_email: T::Boolean).void }
      def disable_mobile_chat!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(mobile_chat: :disabled)
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotMobileChatMailer.mobile_chat_disabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.mobile_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(send_email: T::Boolean).void }
      def enable_mobile_chat!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(mobile_chat: :enabled)
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotMobileChatMailer.mobile_chat_enabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.mobile_chat_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def chat_disabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled_disabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def no_chat_policy?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled_no_policy?
        end
      end

      sig { override.params(send_email: T::Boolean).void }
      def disable_chat!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(chat_enabled: :disabled)
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotForBusinessMailer.chat_disabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.chat_enabled_disabled",
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
      def dotcom_chat_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.dotcom_chat_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def beta_features_github_chat_disable!
        return if beta_features_github_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.beta_features_github_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.beta_features_github_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def beta_features_github_chat_disabled?
        !beta_features_github_chat_enabled?
      end

      sig { override.void }
      def beta_features_github_chat_enable!
        # Beta features can only be toggled at the org level if there is no business policy
        return if beta_features_github_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.beta_features_github_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.beta_features_github_chat_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def beta_features_github_chat_enabled?
        # use the business policy for beta features if it exists, otherwise use the org setting
        if beta_features_github_chat_policy_inherited?
          T.must(copilot_business).beta_features_github_chat_enabled?
        else
          configuration.beta_features_github_chat_enabled?
        end
      end


      sig { override.void }
      def bing_github_chat_disable!
        # Bing can only be toggled at the org level if there is no business policy
        return if bing_github_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.bing_github_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.bing_github_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_bing_github_chat_disable!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.bing_github_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.bing_github_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def bing_github_chat_disabled?
        !bing_github_chat_enabled?
      end

      sig { override.void }
      def bing_github_chat_enable!
        # Bing can only be toggled at the org level if there is no business policy
        return if bing_github_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.bing_github_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.bing_github_chat_enabled",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_bing_github_chat_enable!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.bing_github_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.bing_github_chat_enabled",
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

      sig { returns(T::Boolean) }
      def beta_features_github_chat_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).beta_features_github_chat_no_policy?
      end

      sig { returns(T::Boolean) }
      def bing_github_chat_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).bing_github_chat_no_policy?
      end

      sig { void }
      def disable_user_feedback!
        # User feedback can only be toggled at the org level if there is no business policy
        return if user_feedback_opt_in_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.user_feedback_opt_in_disabled!
        end
      end

      sig { void }
      def enable_user_feedback!
        # User feedback can only be toggled at the org level if there is no business policy
        return if user_feedback_opt_in_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.user_feedback_opt_in_enabled!
        end
      end

      sig { override.returns(T::Boolean) }
      def user_feedback_opt_in_enabled?
        # use the business policy for user feedback if it exists, otherwise use the org setting
        if user_feedback_opt_in_policy_inherited?
          T.must(copilot_business).user_feedback_opt_in_enabled?
        else
          configuration.user_feedback_opt_in_enabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def user_feedback_opt_in_disabled?
        !user_feedback_opt_in_enabled?
      end

      sig { returns(T::Boolean) }
      def user_feedback_opt_in_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).user_feedback_opt_in_no_policy?
      end

      sig { override.returns(T::Boolean) }
      def allow_public_code_suggestions?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_allowed?
        end
      end

      sig { override.returns(T::Boolean) }
      def block_public_code_suggestions?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_blocked?
        end
      end

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

      sig { override.void }
      def copilot_extensions_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_extensions_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_extensions_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def copilot_extensions_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_extensions_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_extensions_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def private_telemetry_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_telemetry_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_telemetry_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def private_telemetry_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_telemetry_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_telemetry_disabled",
          tags: ["type:organization"],
        )
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

      sig { override.returns(String) }
      def chat_setting
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled
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

      sig do
        abstract.type_parameters(:A).params(
          name: String,
          tags: T::Hash[Symbol, String],
          block: T.proc.returns(T.type_parameter(:A)),
        ).returns(T.type_parameter(:A))
      end
      def collect_metrics(name, **tags, &block); end

      sig { override.returns(Configurable) }
      def configurable_object
        organization_object
      end

      # Check whether the associated Copilot::Configuration object is enabled.
      # This method exists solely to check the old configuration of the org when it's added to a parent enterprise,
      # to determine whether or not we should send a notification email.
      #
      # Do not use this to determine if Copilot is enabled for an org!
      #
      # Instead, use `copilot_enabled?`, which checks the parent enterprise's configuration, if one exists.
      sig { override.returns(T::Boolean) }
      def copilot_configuration_setting_enabled?
        configuration.enabled?
      end

      sig { override.void }
      def custom_models_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.custom_models_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.custom_models_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def custom_models_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.custom_models_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.custom_models_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def custom_models_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.custom_models_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def copilot_for_dotcom_unconfigured!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_unconfigured!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_unconfigured",
          tags: ["type:organization"],
        )
      end

      sig { override.params(send_email: T::Boolean).void }
      def copilot_for_dotcom_disabled!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_disabled!
        end

        if send_email && organization_object.business.present?
          business = T.must(organization_object.business)

          if !(copilot_plan_business? && business_trial&.copilot_plan_enterprise? && business_trial&.expired?)
            # trial_expired email is sent when the CE trial has expired
            CopilotEnterpriseMailer.copilot_in_dotcom_disabled_for_organization(organization_object).deliver_later
          end

          Copilot::Seat.for_organization(organization_object).each do |seat|
            if copilot_plan_enterprise? || (business_trial&.copilot_plan_enterprise? && business_trial&.active?) || (business_trial&.copilot_plan_enterprise? && business_trial&.canceled?)
              CopilotEnterpriseMailer.copilot_in_dotcom_disabled_for_user(organization_object, seat.assigned_user).deliver_later
            elsif business.feature_enabled?(:copilot_for_enterprise)
              # Send an email if the user had access via the waitlist
              CopilotEnterpriseMailer.cfe_disabled_for_user(organization_object, seat.assigned_user).deliver_later
            elsif business_trial&.copilot_plan_enterprise? && business_trial&.expired?
              # Send an email if the enterprise is not on Copilot Enterprise plan and the user had access via Copilot Enterprise trial which has expired
              CopilotEnterpriseMailer.trial_expired_for_user(organization_object, seat.assigned_user).deliver_later
            end
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(send_email: T::Boolean).void }
      def copilot_for_dotcom_enabled!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_enabled!
        end

        if business_trial&.copilot_plan_enterprise? &&
            business_trial&.startable?(skip_copilot_for_dotcom_enabled_check: true) &&
            Copilot::Seat.for_organization(organization_object).any?
          T.must(business_trial).start_trial!
        end

        if send_email
          has_enterprise_plan = copilot_plan_enterprise? || business_trial&.copilot_plan_enterprise?
          has_active_trial = !!business_trial&.active?
          business_in_ce_early_access = organization_object.business&.feature_enabled?(:copilot_for_enterprise)

          Copilot::Seat.for_organization(organization_object).each do |seat|
            if business_in_ce_early_access
              CopilotEnterpriseMailer.cfe_enabled_for_user(organization_object, seat.assigned_user).deliver_later
            elsif has_enterprise_plan
              CopilotEnterpriseMailer.upgrade_individual(organization_object, seat.assigned_user, has_active_trial).deliver_later
            end
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_enabled",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def has_mixed_licenses?
        feature_enabled?(:copilot_mixed_licenses)
      end

      sig { override.void }
      def copilot_for_dotcom_no_policy!
        if has_mixed_licenses?
          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.copilot_for_dotcom_no_policy!
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { override.params(send_email: T::Boolean).void }
      def cli_disabled!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.cli_disabled!
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotForBusinessMailer.cli_disabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.cli_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(send_email: T::Boolean).void }
      def cli_enabled!(send_email = true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.cli_enabled!
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotForBusinessMailer.cli_enabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.cli_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def cli_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.cli_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def a_chat_disabled!
        return if a_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def a_chat_enabled!
        return if a_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def a_chat_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_a_chat_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_enabled",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_a_chat_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def a_chat_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).a_chat_no_policy? || T.must(copilot_business).a_chat_unconfigured?)
      end

      sig { override.void }
      def g_chat_disabled!
        return if g_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def g_chat_enabled!
        return if g_chat_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def g_chat_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_g_chat_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_enabled",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_g_chat_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_disabled",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def g_chat_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).g_chat_no_policy? || T.must(copilot_business).g_chat_unconfigured?)
      end

      sig { override.void }
      def o1_disabled!
        return if o1_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o1_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o1_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def o1_enabled!
        return if o1_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o1_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o1_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def o1_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o1_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_o1_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o1_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o1_enabled",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_o1_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o1_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o1_disabled",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def o1_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).o1_no_policy? || T.must(copilot_business).o1_unconfigured?)
      end

      sig { override.void }
      def pr_summarizations_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.pr_summarizations_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.pr_summarizations_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def pr_summarizations_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.pr_summarizations_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.pr_summarizations_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def pr_summarizations_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.pr_summarizations_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def private_docs_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_docs_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_docs_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def private_docs_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_docs_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_docs_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def private_docs_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.private_docs_no_policy",
          tags: ["type:organization"],
        )
      end

      # Does this org have CE access via the waitlist, a trial, or some other mechanism? If they have the
      # CE setting enabled, should they be able to use CE features?
      sig { returns(T::Boolean) }
      def eligible_for_copilot_enterprise?
        return true if copilot_plan_enterprise?

        return true if Copilot::BusinessTrial.active.exists?(
          trialable_id: organization_object.id,
          trialable_type: "Organization",
          copilot_plan: "enterprise"
        )

        return true if organization_object.business&.feature_enabled?(:copilot_for_enterprise)

        false
      end

      sig { override.params(from_config: T::Boolean).returns(String) }
      def copilot_plan(from_config: false)
        if has_mixed_licenses?
          # Because this method returns business if there are mixed licenses and the plan is unconfigured, we need
          # to be able to get the underlying plan from the config to ensure our instrumentation is correct.
          return configuration.copilot_plan if from_config
          return configuration.copilot_plan if has_configured_copilot_plan?
        elsif copilot_business
          return T.must(copilot_business).copilot_plan
        end

        "business"
      end

      sig { returns(T::Boolean) }
      def copilot_plan_business?
        if has_mixed_licenses?
          if configuration.copilot_plan == "unconfigured"
            return true
          else
            return configuration.copilot_plan_business?
          end
        end

        copilot_plan == "business"
      end

      sig { returns(T::Boolean) }
      def copilot_plan_enterprise?
        return configuration.copilot_plan_enterprise? if has_mixed_licenses?

        copilot_plan == "enterprise"
      end

      sig { override.params(send_email: T::Boolean).void }
      def copilot_plan_downgrade!(send_email = true)
        return unless has_mixed_licenses?

        old_plan = copilot_plan
        ActiveRecord::Base.connected_to(role: :writing) do
          copilot_plan_business!(send_email)
          cancel_copilot_plan_downgrade!
        end

        Copilot::Instrumenter.instrument_copilot_plan_changed(nil, organization_object, old_plan, "business")
      end

      sig { params(actor: T.nilable(::User)).void }
      def schedule_copilot_plan_downgrade!(actor = nil)
        return unless has_mixed_licenses?
        return unless copilot_plan_enterprise?
        return unless copilot_business.present?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update(pending_plan_downgrade_date: organization_object.next_metered_billing_cycle_starts_at)
        end

        GitHub.dogstats.increment(
          "copilot.settings.schedule_copilot_plan_downgrade",
          tags: ["type:organization"],
        )

        Copilot::Instrumenter.instrument_copilot_plan_downgrade_scheduled(actor, organization_object, "enterprise", "business")
      end

      sig { void }
      def cancel_copilot_plan_downgrade!
        return unless has_mixed_licenses?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(pending_plan_downgrade_date: nil)
        end
      end

      sig { override.returns(T::Hash[Symbol, T.any(Integer, Symbol)]) }
      def configuration_defaults
        defaults = T.let({}, T::Hash[Symbol, T.any(Integer, Symbol)])

        if copilot_business&.copilot_enabled_for_all_organizations?
          defaults[:copilot_enabled] = :enabled
        end

        defaults[:public_code_suggestions] =
          case copilot_business&.snippy_setting
          when "enabled" then :blocked
          when "disabled" then :allowed
          else :blocked
          end

        defaults[:chat_enabled] =
          case copilot_business&.chat_setting
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:custom_models] =
          case copilot_business&.custom_models_setting
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:dotcom_chat] =
          case copilot_business&.dotcom_chat_setting
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:bing_github_chat] = if copilot_business&.bing_github_chat_enabled?
          :enabled
        else
          :disabled
        end

        defaults[:beta_features_github_chat] = if copilot_business&.beta_features_github_chat_enabled?
          :enabled
        else
          :disabled
        end

        defaults[:user_feedback_opt_in] = :enabled

        defaults[:cli] =
          case copilot_business&.cli
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:a_chat] =
          case copilot_business&.a_chat
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:g_chat] =
          case copilot_business&.g_chat
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:o1] =
          case copilot_business&.o1
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:mobile_chat] =
          case copilot_business&.mobile_chat
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :disabled
          end

        defaults[:pr_summarizations] =
          case copilot_business&.pr_summarizations
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:usage_telemetry_api] = :disabled
        defaults[:user_telemetry] = :disabled
        defaults[:max_seats] = 0
        defaults[:copilot_plan] = :unconfigured
        defaults
      end

      sig { params(send_email: T::Boolean).void }
      def copilot_plan_enterprise!(send_email = true)
        return unless has_mixed_licenses?
        return if business_trial&.active?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_plan_enterprise!
        end

        if send_email
          CopilotEnterpriseMailer.welcome_org_admins(organization_object).deliver_later
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotEnterpriseMailer.welcome_individual(organization_object, seat.assigned_user).deliver_later
          end
        end
      end

      sig { params(send_email: T::Boolean).void }
      def copilot_plan_business!(send_email = true)
        return unless has_mixed_licenses?
        return if business_trial&.active?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_plan_business!
        end

        if send_email
          CopilotForBusinessMailer.welcome_org_admins(organization_object).deliver_later
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotForBusinessMailer.welcome_individual(organization_object, seat.assigned_user).deliver_later
          end
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_configured_copilot_plan?
        has_configuration? && !configuration.copilot_plan_unconfigured?
      end
    end
  end
end
