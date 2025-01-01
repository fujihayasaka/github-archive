# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Settings
      extend T::Helpers
      include Copilot::Helpers
      include Copilot::Organizations::FeatureEnabled
      include Copilot::Organizations::Signatures
      include GitHub::Memoizer

      include Copilot::Organizations::Settings::Models
      include Copilot::Organizations::Settings::Policies
      include Copilot::Organizations::Settings::McpRegistries

      abstract!

      include HasConfiguration

      delegate :copilot_for_dotcom, :copilot_for_dotcom_unconfigured?, :copilot_for_dotcom_configured?, :copilot_for_dotcom_enabled?,
               :copilot_for_dotcom_disabled?, :copilot_for_dotcom_no_policy?, :copilot_for_dotcom_chat_enabled?, :copilot_for_dotcom_setting,
               :mobile_chat, :mobile_chat_no_policy?,
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
               :editor_preview_features, :editor_preview_features_unconfigured?, :editor_preview_features_configured?, :editor_preview_features_enabled?,
               :editor_preview_features_disabled?, :editor_preview_features_no_policy?,
               :agent_mode, :agent_mode_unconfigured?, :agent_mode_configured?, :agent_mode_enabled?,
               :agent_mode_disabled?, :agent_mode_no_policy?,
               :automatic_code_review, :automatic_code_review_unconfigured?, :automatic_code_review_configured?, :automatic_code_review_enabled?,
               :automatic_code_review_disabled?, :automatic_code_review_no_policy?,
               :a_f, :a_f_unconfigured?, :a_f_configured?, :a_f_enabled?,
               :a_f_disabled?, :a_f_no_policy?,
               :afos, :afos_unconfigured?, :afos_enabled?,
               :afos_disabled?, :afos_no_policy?,
               :al, :al_unconfigured?, :al_enabled?,
               :al_disabled?, :al_no_policy?,
               :g_tf, :g_tf_unconfigured?, :g_tf_enabled?,
               :g_tf_disabled?, :g_tf_no_policy?,
               :o1, :o1_unconfigured?, :o1_configured?, :o1_enabled?,
               :o1_disabled?, :o1_no_policy?,
               :o_ff, :o_ff_unconfigured?, :o_ff_configured?, :o_ff_enabled?,
               :o_ff_disabled?, :o_ff_no_policy?,
               :o_fm, :o_fm_unconfigured?, :o_fm_enabled?,
               :o_fm_disabled?, :o_fm_no_policy?,
               :ofct, :ofct_unconfigured?, :ofct_enabled?,
               :ofct_disabled?, :ofct_no_policy?,
               :o_f, :o_f_unconfigured?, :o_f_configured?, :o_f_enabled?,
               :o_f_disabled?, :o_f_no_policy?,
               :o_t, :o_t_unconfigured?, :o_t_enabled?,
               :o_t_disabled?, :o_t_no_policy?,
               :overages, :overages_unconfigured?, :overages_configured?, :overages_enabled?,
               :overages_disabled?, :overages_no_policy?,
               :swe_agent, :swe_agent_no_policy?, :swe_agent_unconfigured?,
               :mcp, :mcp_no_policy?, :mcp_unconfigured?,
               :spark, :spark_no_policy?,
               :insights_no_policy?, :insights_unconfigured?,
               :code_review, :code_review_no_policy?, :code_review_unconfigured?,
               :code_review_beta_features, :code_review_beta_features_no_policy?,
               to: :configuration

      # Please don't add aliases unless you need them.

      sig { override.returns(T.nilable(::Customer)) }
      def customer
        organization_object.customer
      end

      sig { override.returns(T::Boolean) }
      def show_csv_exports?
        organization_object.feature_flag_enabled_or_raise?(:copilot_show_csv_exports) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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
          case T.must(copilot_business).usage_telemetry_api
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
        return true if organization_object.feature_flag_enabled_or_raise?(:copilot_for_business_free) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return true if organization_object.business.present? && organization_object.business&.feature_flag_enabled_or_raise?(:copilot_for_business_free) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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

        previously_enabled = ActiveRecord::Base.connected_to(role: :reading) do
          configuration.enabled?
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.enabled!
        end

        # I do not love having this job be sync, but I think it should execute fairly quickly, in most cases.
        # Ideally we can see how it performs with some larger orgs and figure out an alternative if necessary.
        # Calling this sync becuase we need to guarantee seat assignments have been reinstated before org
        # admins touch seat management settings, otherwise the code in state.rb is going to behave incorrectly.
        # It feels safer to add this job than to make major changes to state.rb, which has implications for all of the
        # Copilot UI functionality.
        if !previously_enabled && feature_enabled?(:copilot_revokable_access)
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: organization_object.id,
            reason: :copilot_enabled
          )
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
      def mobile_chat_disabled!(send_email = true)
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
      def mobile_chat_enabled!(send_email = true)
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

      sig { override.params(force: T::Boolean).void }
      def beta_features_github_chat_disabled!(force: false)
        return if beta_features_github_chat_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.beta_features_github_chat_disabled!
        end

        if code_review_simultaneous_writes_enabled?
          code_review_beta_features_disabled!
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

      sig { override.params(force: T::Boolean).void }
      def beta_features_github_chat_enabled!(force: false)
        # Beta features can only be toggled at the org level if there is no business policy
        return if beta_features_github_chat_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.beta_features_github_chat_enabled!
        end

        if code_review_simultaneous_writes_enabled?
          code_review_beta_features_enabled!
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



      sig { returns(T::Boolean) }
      def beta_features_github_chat_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).beta_features_github_chat_no_policy?
      end

      sig { params(force: T::Boolean).void }
      def disable_user_feedback!(force: false)
        # User feedback can only be toggled at the org level if there is no business policy
        return if user_feedback_opt_in_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.user_feedback_opt_in_disabled!
        end
      end

      sig { params(force: T::Boolean).void }
      def enable_user_feedback!(force: false)
        # User feedback can only be toggled at the org level if there is no business policy
        return if user_feedback_opt_in_policy_inherited? && !force

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
      def chat_setting
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled
        end
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

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_disabled",
          tags: ["type:organization"],
        )

        if code_review_simultaneous_writes_enabled?
          code_review_disabled!
        end
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

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_enabled",
          tags: ["type:organization"],
        )

        if code_review_simultaneous_writes_enabled?
          code_review_enabled!
        end
      end

      sig { override.void }
      def copilot_for_dotcom_no_policy!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_no_policy!
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


      sig { override.params(force: T::Boolean).void }
      def editor_preview_features_disabled!(force: false)
        return if editor_preview_features_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.editor_preview_features_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.editor_preview_features_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def editor_preview_features_enabled!(force: false)
        return if editor_preview_features_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.editor_preview_features_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.editor_preview_features_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def editor_preview_features_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.editor_preview_features_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def editor_preview_features_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).editor_preview_features_no_policy? || T.must(copilot_business).editor_preview_features_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def automatic_code_review_disabled!(force: false)
        return if automatic_code_review_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.automatic_code_review_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.automatic_code_review_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def agent_mode_disabled!(force: false)
        return if agent_mode_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.agent_mode_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def agent_mode_enabled!(force: false)
        return if agent_mode_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.agent_mode_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def agent_mode_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def agent_mode_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).agent_mode_no_policy? || T.must(copilot_business).agent_mode_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def automatic_code_review_enabled!(force: false)
        return if automatic_code_review_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.automatic_code_review_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.automatic_code_review_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def automatic_code_review_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.automatic_code_review_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def automatic_code_review_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).automatic_code_review_no_policy? || T.must(copilot_business).automatic_code_review_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def a_f_disabled!(force: false)
        return if a_f_policy_inherited? && !force
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_f_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_f_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def a_f_enabled!(force: false)
        return if a_f_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_f_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_f_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def a_f_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.a_f_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def a_f_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).a_f_no_policy? || T.must(copilot_business).a_f_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def afos_disabled!(force: false)
        return if afos_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.afos_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.afos_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def afos_enabled!(force: false)
        return if afos_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.afos_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.afos_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def afos_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.afos_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def afos_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).afos_no_policy? || T.must(copilot_business).afos_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def al_disabled!(force: false)
        return if al_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.al_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.al_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def al_enabled!(force: false)
        return if al_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.al_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.al_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def al_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.al_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def al_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).al_no_policy? || T.must(copilot_business).al_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def g_tf_disabled!(force: false)
        return if g_tf_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_tf_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_tf_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def g_tf_enabled!(force: false)
        return if g_tf_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_tf_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_tf_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def g_tf_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.g_tf_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def g_tf_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).g_tf_no_policy? || T.must(copilot_business).g_tf_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def o1_disabled!(force: false)
        return if o1_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o1_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o1_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def o1_enabled!(force: false)
        return if o1_policy_inherited? && !force

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

      sig { returns(T::Boolean) }
      def o1_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).o1_no_policy? || T.must(copilot_business).o1_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def o_ff_disabled!(force: false)
        return if o_ff_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_ff_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_ff_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def o_ff_enabled!(force: false)
        return if o_ff_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_ff_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_ff_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def o_ff_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o_ff_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def o_ff_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).o_ff_no_policy? || T.must(copilot_business).o_ff_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def o_fm_disabled!(force: false)
        return if o_fm_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_fm_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_fm_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def o_fm_enabled!(force: false)
        return if o_fm_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_fm_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_fm_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def o_fm_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o_fm_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def o_fm_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).o_fm_no_policy? || T.must(copilot_business).o_fm_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def ofct_disabled!(force: false)
        return if ofct_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.ofct_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.ofct_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def ofct_enabled!(force: false)
        return if ofct_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.ofct_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.ofct_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def ofct_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.ofct_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def ofct_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).ofct_no_policy? || T.must(copilot_business).ofct_unconfigured?)
      end

      sig { override.params(force: T::Boolean).void }
      def o_f_disabled!(force: false)
        return if o_f_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_f_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_f_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def o_f_enabled!(force: false)
        return if o_f_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_f_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_f_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def o_f_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o_f_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def o_f_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).o_f_no_policy? || T.must(copilot_business).o_f_unconfigured?)
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

      sig { override.params(force: T::Boolean).void }
      def o_t_disabled!(force: false)
        return if o_t_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_t_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_t_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.params(force: T::Boolean).void }
      def o_t_enabled!(force: false)
        return if o_t_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_t_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_t_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def o_t_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o_t_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def o_t_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).o_t_no_policy? || T.must(copilot_business).o_t_unconfigured?)
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

      sig { override.void }
      def overages_disabled!
        return if overages_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.overages_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.overages_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def overages_enabled!
        return if overages_policy_inherited?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.overages_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.overages_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.void }
      def overages_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.overages_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_overages_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.overages_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.overages_enabled",
          tags: ["type:organization"],
        )
      end

      sig { void }
      def force_overages_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.overages_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.overages_disabled",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def overages_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).overages_no_policy? || T.must(copilot_business).overages_unconfigured?)
      end

      sig { override.params(force: T::Boolean, send_email: T::Boolean).void }
      def swe_agent_disabled!(force: false, send_email: true)
        return if swe_agent_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.swe_agent_disabled!
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotSweAgentMailer.swe_agent_disabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.swe_agent_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def swe_agent_disabled?
        !swe_agent_enabled?
      end

      sig { override.params(force: T::Boolean, send_email: T::Boolean).void }
      def swe_agent_enabled!(force: false, send_email: true)
        return if swe_agent_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.swe_agent_enabled!
        end

        if send_email
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotSweAgentMailer.swe_agent_enabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.swe_agent_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def swe_agent_enabled?
        # Use the business policy for SWE agent if it exists, otherwise use the org setting
        if swe_agent_policy_inherited?
          T.must(copilot_business).swe_agent_enabled?
        else
          configuration.swe_agent_enabled?
        end
      end

      sig { override.void }
      def swe_agent_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.swe_agent_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def swe_agent_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).swe_agent_no_policy? || T.must(copilot_business).swe_agent_unconfigured?)
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

        return true if organization_object.business&.feature_flag_enabled_or_raise?(:copilot_for_enterprise) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        false
      end

      sig { override.params(force: T::Boolean).void }
      def mcp_disabled!(force: false)
        return if mcp_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.mcp_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.mcp_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def mcp_disabled?
        !mcp_enabled?
      end

      sig { override.params(force: T::Boolean).void }
      def mcp_enabled!(force: false)
        return if mcp_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.mcp_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.mcp_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def mcp_enabled?
        if mcp_policy_inherited?
          T.must(copilot_business).mcp_enabled?
        else
          configuration.mcp_enabled?
        end
      end

      sig { override.void }
      def mcp_no_policy!
        GitHub.dogstats.increment(
          "copilot.settings.mcp_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def mcp_policy_inherited?
        return false unless copilot_business
        !(T.must(copilot_business).mcp_no_policy? || T.must(copilot_business).mcp_unconfigured?)
      end

      sig { override.params(force: T::Boolean, send_email: T::Boolean).void }
      def spark_disabled!(force: false, send_email: true)
        return if spark_policy_inherited? && !force

        copilot_organization = Copilot::Organization.new(organization_object)
        return unless copilot_organization.feature_flag_enabled_or_raise?(:spark_access_copilot_policy) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.spark_disabled!
        end

        if send_email && copilot_organization.feature_flag_enabled_or_raise?(:spark_access_policy_emails) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotSparkMailer.spark_disabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.spark_disabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def spark_disabled?
        !spark_enabled?
      end

      sig { override.params(force: T::Boolean, send_email: T::Boolean).void }
      def spark_enabled!(force: false, send_email: true)
        return if spark_policy_inherited? && !force

        copilot_organization = Copilot::Organization.new(organization_object)
        return unless copilot_organization.feature_flag_enabled_or_raise?(:spark_access_copilot_policy) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.spark_enabled!
        end

        if send_email && copilot_organization.feature_flag_enabled_or_raise?(:spark_access_policy_emails) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotSparkMailer.spark_enabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.spark_enabled",
          tags: ["type:organization"],
        )
      end

      sig { override.returns(T::Boolean) }
      def spark_enabled?
        if spark_policy_inherited?
          T.must(copilot_business).spark_enabled?
        else
          configuration.spark_enabled?
        end
      end

      sig { override.void }
      def spark_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.spark_no_policy",
          tags: ["type:organization"],
        )
      end

      sig { returns(T::Boolean) }
      def spark_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).spark_no_policy?
      end

      sig { override.params(force: T::Boolean).void }
      def insights_disabled!(force: false)
        return if insights_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.insights_disabled!
        end

        GitHub.dogstats.increment("copilot.settings.insights_disabled", tags: ["type:organization"])
      end

      sig { override.returns(T::Boolean) }
      def insights_disabled?
        !insights_enabled?
      end

      sig { override.params(force: T::Boolean).void }
      def insights_enabled!(force: false)
        return if insights_policy_inherited? && !force

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.insights_enabled!
        end

        GitHub.dogstats.increment("copilot.settings.insights_enabled", tags: ["type:organization"])
      end

      sig { override.returns(T::Boolean) }
      def insights_enabled?
        if copilot_business.present? && !copilot_business&.insights_no_policy?
          T.must(copilot_business).insights_enabled?
        else
          configuration.insights_enabled?
        end
      end

      sig { override.void }
      def insights_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment("copilot.settings.insights_no_policy", tags: ["type:organization"])
      end

      sig { returns(T::Boolean) }
      def insights_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).insights_no_policy?
      end

      sig { override.returns(String) }
      def insights
        if insights_policy_inherited?
          T.must(copilot_business).insights
        else
          configuration.insights
        end
      end

      sig { returns(T::Boolean) }
      def can_write_ccr_policy?
        code_review_simultaneous_writes_enabled? || ccr_policy_flag_enabled?
      end

      sig { returns(T::Boolean) }
      def code_review_simultaneous_writes_enabled?
        organization_object.feature_flag_enabled?(:ccr_policy_simultaneous_writes, default: false) && !ccr_policy_flag_enabled?
      end

      sig { returns(T::Boolean) }
      def ccr_policy_flag_enabled?
        organization_object.feature_flag_enabled?(:copilot_code_review_policy, default: false)
      end

      sig { returns(T::Boolean) }
      def code_review_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).code_review_no_policy?
      end


      sig { override.params(force: T::Boolean, send_email: T::Boolean).void }
      def code_review_disabled!(force: false, send_email: true)
        if code_review_policy_inherited? && !force
          increment_code_review_metric("disabled", inherited: true)
          return
        end

        return unless can_write_ccr_policy?


        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.code_review_disabled!
        end

        if send_email && organization_object.feature_flag_enabled?(:copilot_code_review_emails, default: false)
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotCodeReviewMailer.code_review_disabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        increment_code_review_metric("disabled")
      end

      sig { override.returns(T::Boolean) }
      def code_review_disabled?
        !code_review_enabled?
      end

      sig { override.params(force: T::Boolean, send_email: T::Boolean).void }
      def code_review_enabled!(force: false, send_email: true)
        if code_review_policy_inherited? && !force
          increment_code_review_metric("enabled", inherited: true)
          return
        end
        return unless can_write_ccr_policy?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.code_review_enabled!
        end

        if send_email && organization_object.feature_flag_enabled?(:copilot_code_review_emails, default: false)
          Copilot::Seat.for_organization(organization_object).each do |seat|
            CopilotCodeReviewMailer.code_review_enabled_for_user(organization_object, seat.assigned_user).deliver_later
          end
        end

        increment_code_review_metric("enabled")
      end

      sig { override.returns(T::Boolean) }
      def code_review_enabled?
        if code_review_policy_inherited?
          T.must(copilot_business).code_review_enabled?
        else
          configuration.code_review_enabled?
        end
      end

      sig { override.void }
      def code_review_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here
        increment_code_review_metric("no_policy")
      end

      sig { returns(T::Boolean) }
      def code_review_beta_features_policy_inherited?
        return false unless copilot_business
        !T.must(copilot_business).code_review_beta_features_no_policy?
      end

      sig { override.params(force: T::Boolean).void }
      def code_review_beta_features_disabled!(force: false)
        if code_review_beta_features_policy_inherited? && !force
          increment_code_review_metric("beta_features_disabled", inherited: true)
          return
        end
        return unless can_write_ccr_policy?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.code_review_beta_features_disabled!
        end

        increment_code_review_metric("beta_features_disabled")
      end

      sig { override.returns(T::Boolean) }
      def code_review_beta_features_disabled?
        !code_review_beta_features_enabled?
      end

      sig { override.params(force: T::Boolean).void }
      def code_review_beta_features_enabled!(force: false)
        if code_review_beta_features_policy_inherited? && !force
          increment_code_review_metric("beta_features_enabled", inherited: true)
          return
        end
        return unless can_write_ccr_policy?
        return unless code_review_enabled?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.code_review_beta_features_enabled!
        end

        increment_code_review_metric("beta_features_enabled")
      end

      sig { params(name: String, inherited: T::Boolean).void }
      def increment_code_review_metric(name, inherited: false)
        metric_name = "copilot.settings.code_review_#{name}"
        metric_name = "#{metric_name}.inherited" if inherited
        GitHub.dogstats.increment(metric_name, tags: ["type:organization"])
      end

      sig { override.returns(T::Boolean) }
      def code_review_beta_features_enabled?
        if code_review_beta_features_policy_inherited?
          T.must(copilot_business).code_review_beta_features_enabled?
        else
          configuration.code_review_beta_features_enabled?
        end
      end

      sig { override.params(from_config: T::Boolean).returns(String) }
      def copilot_plan(from_config: false)
        # Because this method returns business if there are mixed licenses and the plan is unconfigured, we need
        # to be able to get the underlying plan from the config to ensure our instrumentation is correct.
        with_read do
          if from_config || has_configured_copilot_plan?
            return configuration.copilot_plan
          end
        end

        "business"
      end

      sig { returns(T::Boolean) }
      def copilot_plan_business?
        copilot_plan == "business"
      end

      sig { returns(T::Boolean) }
      def copilot_plan_enterprise?
        copilot_plan == "enterprise"
      end

      sig { override.params(send_email: T::Boolean).void }
      def copilot_plan_downgrade!(send_email = true)
        old_plan = copilot_plan
        ActiveRecord::Base.connected_to(role: :writing) do
          copilot_plan_business!(send_email)
          cancel_copilot_plan_downgrade!
          # Disable policies that require enterprise licenses
          o_ff_disabled!(force: true)
          o_t_disabled!(force: true)
          al_disabled!(force: true)
          mcp_disabled!(force: true)
          swe_agent_disabled!(force: true)
        end

        Copilot::Instrumenter.instrument_copilot_plan_changed(nil, organization_object, old_plan, "business")
      end

      sig { params(actor: T.nilable(::User)).void }
      def schedule_copilot_plan_downgrade!(actor = nil)
        return unless copilot_plan_enterprise?
        return unless copilot_business.present?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update(pending_plan_downgrade_date: organization_object.next_metered_billing_cycle_starts_at)
        end

        if organization_object.next_metered_billing_cycle_starts_at&.day != 1
          GitHub.logger.warn(
            "next_metered_billing_cycle_starts_at was not set to the 1st of the month - schedule_copilot_plan_downgrade",
            "gh.copilot.organization_id": organization_object.id,
            "gh.copilot.pending_plan_downgrade_date": configuration.pending_plan_downgrade_date,
            "gh.copilot.next_metered_billing_cycle_starts_at": organization_object.next_metered_billing_cycle_starts_at,
            "gh.timezone": Time.zone.to_s
          )
        end

        GitHub.dogstats.increment(
          "copilot.settings.schedule_copilot_plan_downgrade",
          tags: ["type:organization"],
        )

        Copilot::Instrumenter.instrument_copilot_plan_downgrade_scheduled(actor, organization_object, "enterprise", "business")
      end

      sig { void }
      def cancel_copilot_plan_downgrade!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(pending_plan_downgrade_date: nil)
        end
      end

      sig { params(org: Copilot::Organization, business: Copilot::Business).returns(T::Boolean) }
      def swe_agent_eligible?(org, business)
        enterprise_enabled = org.copilot_plan_enterprise? || org.on_free_copilot_enterprise_trial?
        business_enabled = org.copilot_plan_business? || org.on_free_copilot_business_trial?
        enterprise_enabled || business_enabled
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
          else :allowed
          end

        defaults[:chat_enabled] =
          case copilot_business&.chat_setting
          when "disabled" then :disabled
          else :enabled
          end

        defaults[:custom_models] =
          case copilot_business&.custom_models
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:dotcom_chat] =
          case copilot_business&.dotcom_chat
          when "enabled" then :enabled
          when "disabled" then :disabled
          when "unconfigured" then :unconfigured # legacy business with "No prompts stored" in their contracts https://github.com/github/copilot-productivity/issues/3134
          else :enabled
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
          when "unconfigured" then :unconfigured # legacy business with "No prompts stored" in their contracts https://github.com/github/copilot-productivity/issues/3134
          else :enabled
          end

        defaults[:desktop] =
          case copilot_business&.desktop
          when "enabled" then :enabled
          when "disabled" then :disabled
          when "unconfigured" then :unconfigured
          else :enabled
          end

        defaults[:editor_preview_features] =
          case copilot_business&.editor_preview_features
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:agent_mode] =
          case copilot_business&.agent_mode
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:automatic_code_review] =
          case copilot_business&.automatic_code_review
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

        defaults[:a_f] =
          case copilot_business&.a_f
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:afos] =
          case copilot_business&.afos
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:al] =
          case copilot_business&.al
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

        defaults[:g_tf] =
          case copilot_business&.g_tf
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:gtff] =
          case copilot_business&.gtff
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

        # defaults[:o3] =
        #   case copilot_business&.o3
        #   when "enabled" then :enabled
        #   when "disabled" then :disabled
        #   else :unconfigured
        #   end
        defaults[:o_ff] =
          case copilot_business&.o_ff
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:o_fm] =
          case copilot_business&.o_fm
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:ofct] =
          case copilot_business&.ofct
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:o_f] =
          case copilot_business&.o_f
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:o_t] =
          case copilot_business&.o_t
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:obmb] =
          case copilot_business&.obmb
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:obmw] =
          case copilot_business&.obmw
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:aofo] =
          case copilot_business&.aofo
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:ofo] =
          case copilot_business&.ofo
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:grok_code] =
          case copilot_business&.grok_code
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:mobile_chat] =
          case copilot_business&.mobile_chat
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :enabled
          end

        defaults[:pr_summarizations] =
          case copilot_business&.pr_summarizations
          when "enabled" then :enabled
          when "disabled" then :disabled
          when "unconfigured" then :unconfigured # legacy business with "No prompts stored" in their contracts https://github.com/github/copilot-productivity/issues/3134
          else :enabled
          end

        defaults[:mcp] =
          case copilot_business&.mcp
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:overages] =
          case copilot_business&.overages
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:swe_agent] =
          case copilot_business&.swe_agent
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:spark] =
          case copilot_business&.spark
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :disabled
          end

        defaults[:insights] =
          case copilot_business&.insights
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:code_review] =
          case copilot_business&.code_review
          when "enabled" then :enabled
          when "disabled" then :disabled
          else :unconfigured
          end

        defaults[:code_review_beta_features] =
          case copilot_business&.code_review_beta_features
          when "enabled" then :enabled
          else :disabled
          end

        defaults[:usage_telemetry_api] = :disabled
        defaults[:user_telemetry] = :disabled
        defaults[:max_seats] = 0
        defaults[:copilot_plan] = :unconfigured
        defaults
      end

      sig { params(send_email: T::Boolean).void }
      def copilot_plan_enterprise!(send_email = true)
        return if business_trial&.active?
        return unless copilot_business.present?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_plan_enterprise!
          # Make sure any premium settings get propagated to the org
          T.must(copilot_business).propagate_settings_for_org!(Copilot::Organization.new(organization_object))
        end

        if send_email
          CopilotEnterpriseMailer.welcome_org_admins(organization_object).deliver_later
          Copilot::Seat.without_access_revoked(owner: organization_object).each do |seat|
            CopilotEnterpriseMailer.welcome_individual(
              organization_object,
              seat.assigned_user
            ).deliver_later
          end
        end
      end

      sig { params(send_email: T::Boolean).void }
      def copilot_plan_business!(send_email = true)
        return if business_trial&.active?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_plan_business!
        end

        if send_email
          CopilotForBusinessMailer.welcome_org_admins(organization_object).deliver_later
          Copilot::Seat.without_access_revoked(owner: organization_object).each do |seat|
            CopilotForBusinessMailer.welcome_individual(
              organization_object,
              seat.assigned_user
            ).deliver_later
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
