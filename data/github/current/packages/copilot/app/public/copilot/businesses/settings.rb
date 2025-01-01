# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Settings
      extend T::Helpers
      include Copilot::Helpers
      include Copilot::Businesses::Licensing
      include Copilot::Businesses::Signatures
      include Copilot::Businesses::Trials

      abstract!

      include HasConfiguration

      delegate :copilot_for_dotcom, :copilot_for_dotcom_unconfigured?, :copilot_for_dotcom_configured?, :copilot_for_dotcom_enabled?,
               :copilot_for_dotcom_disabled?, :copilot_for_dotcom_no_policy?, :copilot_for_dotcom_chat_enabled?, :copilot_for_dotcom_setting,
               :dotcom_chat, :dotcom_chat_unconfigured?, :dotcom_chat_configured?, :dotcom_chat_enabled?,
               :dotcom_chat_disabled?, :dotcom_chat_no_policy?, :dotcom_chat_chat_enabled?, :mobile_chat,
               :mobile_chat_enabled?, :mobile_chat_disabled?, :mobile_chat_no_policy?,
               :custom_models, :custom_models_unconfigured?, :custom_models_configured?, :custom_models_enabled?,
               :custom_models_disabled?, :custom_models_no_policy?, :custom_models_chat_enabled?,
               :cli, :cli_unconfigured?, :cli_configured?, :cli_enabled?,
               :cli_disabled?, :cli_no_policy?, :cli_chat_enabled?,
               :private_docs, :private_docs_unconfigured?, :private_docs_configured?, :private_docs_enabled?,
               :private_docs_disabled?, :private_docs_no_policy?, :private_docs_chat_enabled?,
               :pr_summarizations, :pr_summarizations_unconfigured?, :pr_summarizations_configured?, :pr_summarizations_enabled?,
               :pr_summarizations_disabled?, :pr_summarizations_no_policy?, :pr_summarizations_chat_enabled?,
               :usage_telemetry_api,
               :copilot_plan, :copilot_plan_enterprise!, :copilot_plan_business!, :pending_plan_downgrade_date, :copilot_plan_business?, :copilot_plan_enterprise?,
               :copilot_extensions, :copilot_extensions_unconfigured?, :copilot_extensions_configured?,
               :copilot_extensions_enabled?, :copilot_extensions_disabled?, :copilot_extensions_no_policy?,
               :beta_features_github_chat, :bing_github_chat, :bing_github_chat_disabled?, :bing_github_chat_enabled?,
               :private_telemetry, :private_telemetry_unconfigured?, :private_telemetry_configured?,
               :private_telemetry_enabled?, :private_telemetry_disabled?, :private_telemetry_no_policy?,
               :editor_preview_features, :editor_preview_features_unconfigured?, :editor_preview_features_configured?, :editor_preview_features_enabled?, :editor_preview_features_disabled?, :editor_preview_features_no_policy?,
               :a_chat, :a_chat_unconfigured?, :a_chat_configured?, :a_chat_enabled?, :a_chat_disabled?, :a_chat_no_policy?,
               :a_f, :a_f_unconfigured?, :a_f_configured?, :a_f_enabled?, :a_f_disabled?, :a_f_no_policy?,
               :g_chat, :g_chat_unconfigured?, :g_chat_configured?, :g_chat_enabled?, :g_chat_disabled?, :g_chat_no_policy?,
               :o1, :o1_unconfigured?, :o1_configured?, :o1_enabled?, :o1_disabled?, :o1_no_policy?,
               :o3, :o3_unconfigured?, :o3_configured?, :o3_enabled?, :o3_disabled?, :o3_no_policy?,
               :o_ff, :o_ff_unconfigured?, :o_ff_configured?, :o_ff_enabled?, :o_ff_disabled?, :o_ff_no_policy?,
               :o_f, :o_f_unconfigured?, :o_f_configured?, :o_f_enabled?, :o_f_disabled?, :o_f_no_policy?,
               :workspace_for_emu, :workspace_for_emu_disabled?, :workspace_for_emu_enabled?,
               :desktop, :desktop_unconfigured?, :desktop_configured?, :desktop_enabled?, :desktop_disabled?, :desktop_no_policy?,
               :overages, :overages_unconfigured?, :overages_configured?, :overages_enabled?, :overages_disabled?, :overages_no_policy?,
               to: :configuration

      alias dotcom_chat_setting dotcom_chat
      alias custom_models_setting custom_models
      alias cli_setting cli
      alias editor_preview_features_setting editor_preview_features
      alias a_chat_setting a_chat
      alias a_f_setting a_f
      alias af_setting a_f
      alias g_chat_setting g_chat
      alias o1_setting o1
      alias o3_setting o3
      alias o_ff_setting o_ff
      alias off_setting o_ff
      alias o_f_setting o_f
      alias of_setting o_f
      alias private_docs_setting private_docs
      alias pr_summarizations_setting pr_summarizations
      alias usage_telemetry_api_setting usage_telemetry_api
      alias mobile_chat_setting mobile_chat
      alias copilot_extensions_setting copilot_extensions
      alias private_telemetry_setting private_telemetry
      alias bing_github_chat_setting bing_github_chat
      alias desktop_setting desktop
      alias overages_setting overages

      sig { override.returns(T::Boolean) }
      def copilot_standalone?
        business_object.copilot_licensing_enabled?
      end

      sig { override.returns(T.nilable(::Customer)) }
      def customer
        business_object.customer
      end

      # whether the organization has been feature flagged to not be charged
      sig { override.returns(T::Boolean) }
      def copilot_for_business_free?
        business_object.feature_enabled?(:copilot_for_business_free)
      end

      sig { override.returns(Integer) }
      def copilot_max_seats
        with_read do
          configuration.max_seats
        end
      end

      sig { override.params(value: Integer).void }
      def copilot_max_seats=(value)
        with_write do
          GitHub.logger.info("Updating Business Max Copilot Seats")
          configuration.update!(max_seats: value)
        end
      end

      # Simply by existing, an Enterprise has access to Copilot
      # We cannot remove this function entirely because it's used
      # by Configurable
      sig { override.returns(T::Boolean) }
      def copilot_for_business_enabled?
        true
      end

      sig { override.returns(String) }
      def copilot_business_enablement_setting
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.copilot_enabled
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_disabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.disabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_unconfigured?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.unconfigured?
        end
      end

      sig { void }
      def copilot_unconfigured!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.unconfigured!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_unconfigured",
          tags: ["type:business"],
        )
      end

      sig { override.returns(T::Boolean) }
      def copilot_enabled?
        return true if business_object.digital_front_door?
        !copilot_disabled? && !copilot_unconfigured?
      end

      # Disables Copilot for this business and all of its organizations.
      sig { override.params(actor: T.nilable(::User)).void }
      def disable_copilot!(actor = nil)
        disable_and_notify_organizations(copilot_organizations, actor)

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.disabled!
        end
      end

      sig { void }
      def enable_copilot!
        return unless copilot_standalone?

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.enabled!
        end
      end

      sig { override.returns(Integer) }
      def copilot_enabled_organizations_count
        copilot_enabled_organizations.count
      end

      sig { returns(Integer) }
      def copilot_enabled_members_count
        Copilot::Seat
          .joins(:seat_assignment)
          .where(copilot_seat_assignments: {
            owner_id: business_object.organization_ids,
            owner_type: "Organization"
          })
          .distinct
          .count(:assigned_user_id)
      end

      sig { override.returns(T::Boolean) }
      def has_copilot_organization?
        ActiveRecord::Base.connected_to(role: :reading) do
          return true if copilot_organizations.find(&:copilot_enabled?)
        end
        false
      end

      sig { override.returns(T::Array[Copilot::Organization]) }
      def copilot_enabled_organizations
        ActiveRecord::Base.connected_to(role: :reading) do
          copilot_organizations.select(&:copilot_enabled?)
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_enabled_for_all_organizations?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.all_organizations?
        end
      end

      # Enables Copilot for this business and all of its organizations, and
      # sends an email to each organization admin notifying them of the next
      # steps.
      sig { override.params(actor: T.nilable(::User)).void }
      def enable_copilot_for_all_organizations!(actor =  nil)
        enable_and_notify_organizations(copilot_organizations, actor)

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.all_organizations!
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_enabled_for_selected_organizations?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.selected_organizations?
        end
      end

      sig { returns(String) }
      def copilot_enablement_setting
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.copilot_enabled
        end
      end

      # Enables Copilot for this business and the selected organizations. It
      # does not modify organizations not passed in. Actor can be nil so that we don't instrument this
      # when it's happening via trial upgrade in stafftools
      sig { override.params(org_ids: T::Array[Integer], actor: T.nilable(::User)).void }
      def enable_copilot_for_selected_organizations!(org_ids, actor = nil)
        selected_copilot_organizations = copilot_organizations.select do |copilot_org|
          org_ids.include?(copilot_org.organization_object.id)
        end

        enable_and_notify_organizations(selected_copilot_organizations, actor)

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.selected_organizations!
        end
      end

      # Disables Copilot for the selected organizations. It does not modify
      # organizations not passed in.
      sig { params(org_ids: T::Array[Integer], actor: T.nilable(::User)).void }
      def disable_copilot_for_selected_organizations!(org_ids, actor = nil)
        selected_copilot_organizations = copilot_organizations.select do |copilot_org|
          org_ids.include?(copilot_org.organization_object.id)
        end

        disable_and_notify_organizations(selected_copilot_organizations, actor)

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.selected_organizations!
        end
      end

      sig { override.void }
      def copilot_plan_downgrade!
        return if pending_plan_downgrade_date.nil?
        return unless copilot_plan_enterprise?

        old_plan = Copilot::Business.new(business_object).copilot_plan
        ActiveRecord::Base.connected_to(role: :writing) do
          copilot_plan_business!
          cancel_copilot_plan_downgrade!
        end

        Copilot::Instrumenter.instrument_copilot_plan_changed(nil, business_object, old_plan, "business")
      end

      sig { params(actor: T.nilable(::User)).void }
      def schedule_copilot_plan_downgrade!(actor = nil)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(pending_plan_downgrade_date: business_object.next_metered_billing_cycle_starts_at)
        end

        Copilot::Instrumenter.instrument_copilot_plan_downgrade_scheduled(actor, business_object, "enterprise", "business")
      end

      sig { void }
      def cancel_copilot_plan_downgrade!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(pending_plan_downgrade_date: nil)
        end
      end

      sig { override.returns(T::Boolean) }
      def allow_public_code_suggestions?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_allowed?
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

      sig { override.void }
      def enable_chat!
        update_configuration!("chat_enabled", "enabled", send_email: true)
      end

      sig { override.returns(T::Boolean) }
      def chat_disabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled_disabled?
        end
      end

      sig { override.void }
      def disable_chat!
        update_configuration!("chat_enabled", "disabled", send_email: true)
      end

      sig { override.returns(T::Boolean) }
      def no_chat_policy?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.chat_enabled_no_policy?
        end
      end

      sig { override.void }
      def no_chat_policy!
        update_configuration!("chat_enabled", "no_policy", send_email: false)
      end

      sig { override.returns(T::Boolean) }
      def chat_enabled_configured?
        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.chat_enabled_unconfigured?
        end
      end

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

      sig { void }
      def disable_user_feedback!
        # user feedback can only be toggled if copilot for dotcom is enabled
        return unless copilot_for_dotcom_enabled?

        update_configuration!("user_feedback_opt_in", "disabled", send_email: false)
      end

      sig { void }
      def enable_user_feedback!
        # user feedback can only be toggled if copilot for dotcom is enabled
        return unless copilot_for_dotcom_enabled?

        update_configuration!("user_feedback_opt_in", "enabled", send_email: false)
      end

      sig { override.returns(T::Boolean) }
      def user_feedback_opt_in_enabled?
        return false if user_feedback_opt_in_no_policy?
        return false if copilot_for_dotcom_disabled?

        configuration.user_feedback_opt_in_enabled?
      end

      sig { override.returns(T::Boolean) }
      def user_feedback_opt_in_disabled?
        return false if user_feedback_opt_in_no_policy?
        !user_feedback_opt_in_enabled?
      end

      sig { override.returns(T::Boolean) }
      def user_feedback_opt_in_no_policy?
        # User feedback depends on the copilot for dotcom policy
        copilot_for_dotcom_no_policy?
      end

      sig { override.void }
      def bing_github_chat_disable!
        update_configuration!("bing_github_chat", "disabled", send_email: true)
      end

      sig { override.void }
      def bing_github_chat_enable!
        update_configuration!("bing_github_chat", "enabled", send_email: true)
      end

      sig { override.returns(T::Boolean) }
      def beta_features_github_chat_enabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          return false if copilot_for_dotcom_disabled? #takes precedence

          configuration.beta_features_github_chat_enabled?
        end
      end

      sig { returns(T::Boolean) }
      def beta_features_github_chat_enabled_in_config?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.beta_features_github_chat_enabled?
        end
      end

      sig { returns(T::Boolean) }
      def beta_features_github_chat_no_policy_in_config?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.beta_features_github_chat_no_policy?
        end
      end

      sig { override.returns(T::Boolean) }
      def beta_features_github_chat_disabled?
        return false if beta_features_github_chat_no_policy?
        !beta_features_github_chat_enabled?
      end

      sig { override.returns(T::Boolean) }
      def beta_features_github_chat_no_policy?
        ActiveRecord::Base.connected_to(role: :reading) do
          return true if copilot_for_dotcom_no_policy? #takes precedence

          configuration.beta_features_github_chat_no_policy?
        end
      end

      sig { override.void }
      def beta_features_github_chat_no_policy!
        update_configuration!("beta_features_github_chat", "no_policy", send_email: false)
      end

      sig { override.void }
      def beta_features_github_chat_disable!
        update_configuration!("beta_features_github_chat", "disabled", send_email: false)
      end

      sig { override.void }
      def beta_features_github_chat_enable!
        update_configuration!("beta_features_github_chat", "enabled", send_email: false)
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

      sig { override.void }
      def copilot_for_dotcom_unconfigured!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_unconfigured!
        end

        propagate_organization_settings!

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_unconfigured",
          tags: ["type:business"],
        )
      end

      sig { override.params(send_email: T::Boolean).void }
      def copilot_for_dotcom_disabled!(send_email: true)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_disabled!
        end

        # we explicitly don't send this email when we're onboarding from the enterprise beta
        propagate_organization_settings!(send_email ? :copilot_dotcom : :noop)

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_disabled",
          tags: ["type:business"],
        )
      end

      sig { override.void }
      def copilot_for_dotcom_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_enabled!
        end

        propagate_organization_settings!(:copilot_dotcom)

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_enabled",
          tags: ["type:business"],
        )
      end

      sig { override.params(disable_non_trial_orgs_setting: T::Boolean).void }
      def copilot_for_dotcom_no_policy!(disable_non_trial_orgs_setting: false)
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_no_policy!
        end

        if disable_non_trial_orgs_setting
          non_trialing_orgs = copilot_organizations - copilot_organizations_with_active_trials
          non_trialing_orgs.map(&:copilot_for_dotcom_disabled!)
        else
          propagate_organization_settings!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_no_policy",
          tags: ["type:business"],
        )
      end

      sig { override.void }
      def disable_mobile_chat!
        update_configuration!("mobile_chat", "disabled", send_email: true)
      end

      sig { override.void }
      def enable_mobile_chat!
        update_configuration!("mobile_chat", "enabled", send_email: true)
      end

      sig { void }
      def mobile_chat_no_policy!
        update_configuration!("mobile_chat", "no_policy", send_email: false)
      end

      sig { returns(T::Boolean) }
      def no_mobile_chat_policy?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.mobile_chat_no_policy?
        end
      end

      sig { override.void }
      def pr_summarizations_enabled!
        update_configuration!("pr_summarizations", "enabled", send_email: false)
      end

      sig { override.void }
      def pr_summarizations_disabled!
        update_configuration!("pr_summarizations", "disabled", send_email: false)
      end

      sig { override.void }
      def pr_summarizations_no_policy!
        update_configuration!("pr_summarizations", "no_policy", send_email: false)
      end

      sig { override.void }
      def private_docs_enabled!
        update_configuration!("private_docs", "enabled", send_email: false)
      end

      sig { override.void }
      def private_docs_disabled!
        update_configuration!("private_docs", "disabled", send_email: false)
      end

      sig { override.void }
      def private_docs_no_policy!
        update_configuration!("private_docs", "no_policy", send_email: false)
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

      sig { override.void }
      def copilot_extensions_enabled!
        update_configuration!("copilot_extensions", "enabled", send_email: true)
      end

      sig { override.void }
      def copilot_extensions_disabled!
        update_configuration!("copilot_extensions", "disabled", send_email: true)
      end

      sig { override.void }
      def copilot_extensions_no_policy!
        update_configuration!("copilot_extensions", "no_policy", send_email: true)
      end

      sig { override.void }
      def private_telemetry_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_telemetry_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_telemetry_enabled",
          tags: ["type:business"],
        )
      end

      sig { override.void }
      def private_telemetry_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_telemetry_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_telemetry_disabled",
          tags: ["type:business"],
        )
      end

      sig { override.void }
      def private_telemetry_no_policy!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_telemetry_no_policy!
        end

        propagate_organization_settings!(:private_telemetry)

        GitHub.dogstats.increment(
          "copilot.settings.private_telemetry_no_policy",
          tags: ["type:business"],
        )
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

      sig { override.returns(T::Boolean) }
      def can_emit_usage?
        !configurable_object.feature_enabled?(:copilot_for_business_free)
      end

      sig { override.returns(Configurable) }
      def configurable_object
        business_object
      end

      sig { abstract.returns(::Business) }
      def business_object; end

      sig { override.returns(T::Array[Copilot::Organization]) }
      def copilot_organizations
        business_object.organizations.includes(:business).map do |organization|
          Copilot::Organization.new(organization)
        end
      end

      sig { params(feature: ::Symbol).void }
      def propagate_organization_settings!(feature = :noop)
        if business_object.feature_enabled?(:copilot_batch_update_org_settings_job)
          Copilot::BatchUpdateOrgSettingsJob.perform_later(business_object.id, feature)
        else
          copilot_organizations.each do |copilot_org|
            propagate_settings_for_org!(copilot_org, feature: feature)
            Copilot::BatchUpdateUserSettingsJob.perform_later(copilot_org.id)
          end
        end
      end

      sig { params(copilot_org: Copilot::Organization, feature: ::Symbol).void }
      def propagate_settings_for_org!(copilot_org, feature: :noop)
        if chat_enabled?
          copilot_org.enable_chat!(feature == :chat_enabled)
        end

        if chat_disabled?
          copilot_org.disable_chat!(feature == :chat_enabled)
        end

        if dotcom_chat_enabled?
          # we do not send an email when enabling dotcom chat for an org
          # however it is a parameter so we should honor send_email above
          copilot_org.dotcom_chat_enabled!
        end

        if dotcom_chat_disabled?
          # we do not send an email when disabling dotcom chat for an org
          # however it is a parameter so we should honor send_email above
          copilot_org.disable_dotcom_chat!
        end

        if allow_public_code_suggestions?
          # we do not send an email when allowing public code suggestions for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.allow_public_code_suggestions!
        end

        if block_public_code_suggestions?
          # we do not send an email when blocking public code suggestions for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.block_public_code_suggestions!
        end

        if custom_models_disabled?
          # we do not send an email when disabling custom models for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.custom_models_disabled!
        end

        if custom_models_enabled?
          # we do not send an email when enabling custom models for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.custom_models_enabled!
        end

        if cli_disabled?
          copilot_org.cli_disabled!(feature == :cli)
        end

        if cli_enabled?
          copilot_org.cli_enabled!(feature == :cli)
        end

        if desktop_disabled?
          copilot_org.desktop_disabled!(feature == :desktop)
        end

        if desktop_enabled?
          copilot_org.desktop_enabled!(feature == :desktop)
        end

        if editor_preview_features_disabled?
          copilot_org.editor_preview_features_disabled!(force: true)
        end

        if editor_preview_features_enabled?
          copilot_org.editor_preview_features_enabled!(force: true)
        end

        if a_chat_disabled?
          copilot_org.a_chat_disabled!(force: true)
        end

        if a_chat_enabled?
          copilot_org.a_chat_enabled!(force: true)
        end

        if a_f_disabled?
          copilot_org.a_f_disabled!(force: true)
        end

        if a_f_enabled?
          copilot_org.a_f_enabled!(force: true)
        end

        if g_chat_disabled?
          copilot_org.g_chat_disabled!(force: true)
        end

        if g_chat_enabled?
          copilot_org.g_chat_enabled!(force: true)
        end

        if o1_disabled?
          copilot_org.o1_disabled!(force: true)
        end

        if o1_enabled?
          copilot_org.o1_enabled!(force: true)
        end

        if o3_disabled?
          copilot_org.o3_disabled!(force: true)
        end

        if o3_enabled?
          copilot_org.o3_enabled!(force: true)
        end

        if o_ff_disabled?
          copilot_org.o_ff_disabled!(force: true)
        end

        if o_ff_enabled?
          copilot_org.o_ff_enabled!(force: true)
        end

        if o_f_disabled?
          copilot_org.o_f_disabled!(force: true)
        end

        if o_f_enabled?
          copilot_org.o_f_enabled!(force: true)
        end

        if pr_summarizations_enabled?
          # we do not send an email when enabling pr summarizations for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.pr_summarizations_enabled!
        end

        if pr_summarizations_disabled?
          # we do not send an email when disabling pr summarizations for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.pr_summarizations_disabled!
        end

        if private_docs_enabled?
          # we do not send an email when enabling private docs for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.private_docs_enabled!
        end

        if private_docs_disabled?
          # we do not send an email when disabling private docs for an org
          # if we decide to start sending emails, we should honor send_email above
          copilot_org.private_docs_disabled!
        end

        if copilot_for_dotcom_disabled?
          copilot_org.copilot_for_dotcom_disabled!(feature == :copilot_dotcom)
        end

        if copilot_for_dotcom_enabled?
          copilot_org.copilot_for_dotcom_enabled!(feature == :copilot_dotcom)
        end

        if mobile_chat_disabled?
          copilot_org.disable_mobile_chat!(feature == :mobile_chat)
        end

        if mobile_chat_enabled?
          copilot_org.enable_mobile_chat!(feature == :mobile_chat)
        end

        if copilot_extensions_disabled?
          copilot_org.copilot_extensions_disabled!
        end

        if copilot_extensions_enabled?
          copilot_org.copilot_extensions_enabled!
        end

        if bing_github_chat_enabled?
          copilot_org.bing_github_chat_enable!(force: true)
        end

        if bing_github_chat_disabled?
          copilot_org.bing_github_chat_disable!(force: true)
        end

        if configuration.usage_telemetry_api_enabled?
          copilot_org.telemetry_aggregation_enabled!
        end

        if configuration.usage_telemetry_api_disabled?
          copilot_org.telemetry_aggregation_disabled!
        end

        if user_feedback_opt_in_enabled?
          copilot_org.enable_user_feedback!(force: true)
        end

        if user_feedback_opt_in_disabled?
          copilot_org.disable_user_feedback!(force: true)
        end

        if beta_features_github_chat_enabled?
          copilot_org.beta_features_github_chat_enable!(force: true)
        end

        if beta_features_github_chat_disabled?
          copilot_org.beta_features_github_chat_disable!(force: true)
        end

        if overages_disabled?
          copilot_org.force_overages_disabled!
        end

        if overages_enabled?
          copilot_org.force_overages_enabled!
        end
      end

      # Disables Copilot for the given organizations and sends an email to each
      # organization admin notifying them of the change. Organizations that are
      # already disabled do not receive an email.
      sig { params(copilot_orgs: T::Array[Copilot::Organization], actor: T.nilable(::User)).void }
      def disable_and_notify_organizations(copilot_orgs, actor = nil)
        copilot_orgs.each do |copilot_org|
          next unless copilot_org.copilot_enabled?

          copilot_org.revoke_copilot_for_org!(actor)

          CopilotForBusinessMailer.cfb_disabled_by_business(
            business_object,
            copilot_org.organization_object,
          ).deliver_later
        end
      end

      sig { override.void }
      def custom_models_enabled!
        update_configuration!("custom_models", "enabled", send_email: false)
      end

      sig { override.void }
      def custom_models_no_policy!
        update_configuration!("custom_models", "no_policy", send_email: false)
      end

      sig { override.void }
      def custom_models_disabled!
        update_configuration!("custom_models", "disabled", send_email: false)
      end

      sig { override.void }
      def cli_enabled!
        update_configuration!("cli", "enabled")
      end

      sig { override.void }
      def cli_disabled!
        update_configuration!("cli", "disabled")
      end

      sig { override.void }
      def cli_no_policy!
        update_configuration!("cli", "no_policy", send_email: false)
      end

      sig { override.void }
      def editor_preview_features_enabled!
        update_configuration!("editor_preview_features", "enabled", send_email: true)
      end

      sig { override.void }
      def editor_preview_features_disabled!
        update_configuration!("editor_preview_features", "disabled", send_email: true)
      end

      sig { override.void }
      def editor_preview_features_no_policy!
        update_configuration!("editor_preview_features", "no_policy", send_email: false)
      end

      sig { override.void }
      def a_chat_enabled!
        update_configuration!("a_chat", "enabled", send_email: true)
      end

      sig { override.void }
      def o_f_disabled!
        update_configuration!("o_f", "disabled", send_email: true)
      end

      sig { override.void }
      def a_chat_disabled!
        update_configuration!("a_chat", "disabled", send_email: true)
      end

      sig { override.void }
      def a_chat_no_policy!
        update_configuration!("a_chat", "no_policy", send_email: false)
      end

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

      sig { override.void }
      def o1_enabled!
        update_configuration!("o1", "enabled", send_email: true)
      end

      sig { override.void }
      def o1_disabled!
        update_configuration!("o1", "disabled", send_email: true)
      end

      sig { override.void }
      def o1_no_policy!
        update_configuration!("o1", "no_policy", send_email: false)
      end

      sig { override.void }
      def a_f_enabled!
        update_configuration!("a_f", "enabled", send_email: false)
      end

      sig { override.void }
      def a_f_disabled!
        update_configuration!("a_f", "disabled", send_email: true)
      end

      sig { override.void }
      def a_f_no_policy!
        update_configuration!("a_f", "no_policy", send_email: false)
      end

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

      sig { override.void }
      def o_ff_enabled!
        update_configuration!("o_ff", "enabled", send_email: false)
      end

      sig { override.void }
      def o_ff_disabled!
        update_configuration!("o_ff", "disabled", send_email: true)
      end

      sig { override.void }
      def o_ff_no_policy!
        update_configuration!("o_ff", "no_policy", send_email: false)
      end

      sig { override.void }
      def o_f_enabled!
        update_configuration!("o_f", "enabled", send_email: false)
      end

      sig { override.void }
      def o_f_no_policy!
        update_configuration!("o_f", "no_policy", send_email: false)
      end

      sig { void }
      def workspace_for_emu_enabled!
        update_configuration!("workspace_for_emu", "enabled", send_email: false)
      end

      sig { void }
      def workspace_for_emu_disabled!
        update_configuration!("workspace_for_emu", "disabled", send_email: false)
      end

      sig { override.void }
      def overages_enabled!
        update_configuration!("overages", "enabled", send_email: true)
      end

      sig { override.void }
      def overages_disabled!
        update_configuration!("overages", "disabled", send_email: true)
      end

      sig { override.void }
      def overages_no_policy!
        update_configuration!("overages", "no_policy", send_email: false)
      end

      sig { returns(T::Boolean) }
      def has_copilot_enterprise_access?
        return true if business_object.feature_enabled?(:copilot_for_enterprise)

        configuration.copilot_plan_enterprise?
      end

      sig { returns(T::Boolean) }
      def can_upgrade_to_copilot_enterprise?
        configuration.copilot_plan_business?
      end

      sig { returns(T::Boolean) }
      def is_standalone_business?
        copilot_standalone?
      end

      sig { override.void }
      def telemetry_aggregation_enabled!
        update_configuration!("usage_telemetry_api", "enabled", send_email: false)
      end

      sig { override.void }
      def telemetry_aggregation_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.usage_telemetry_api_disabled!

          # Can we use propagate to orgs here?
          copilot_organizations.each do |copilot_org|
            copilot_org.telemetry_aggregation_disabled!
          end
        end

        GitHub.dogstats.increment(
          "copilot.settings.usage_telemetry_api_disabled",
          tags: ["type:business"],
        )
      end

      sig { override.void }
      def telemetry_aggregation_no_policy!
        update_configuration!("usage_telemetry_api", "no_policy", send_email: false)
      end

      sig { override.returns(T::Boolean) }
      def telemetry_aggregation_enabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          if is_standalone_business?
            configuration.usage_telemetry_api_enabled?
          else
            # NOTE: unlike other policies, this one is considered enabled even if the enterprise is set to no_policy
            # this is because an enterprise admin should be able to hit the **enterprise** metrics endpoint even if the policy
            # allows organizations to pick their own policy about hitting the **organization** endpoint
            configuration.usage_telemetry_api_enabled? || configuration.usage_telemetry_api_no_policy?
          end
        end
      end

      sig { override.returns(T::Boolean) }
      def telemetry_aggregation_disabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.usage_telemetry_api_disabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def telemetry_aggregation_no_policy?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.usage_telemetry_api_no_policy?
        end
      end

      # Helper method that tells us if the Business' Copilot configuration can be migrated to EnterpriseTeams
      # - They have the proper betas (direct memberships + enterprise_teams_migrate_from_cfb)
      # - They must not have a Copilot EnterpriseTeam created with IdP mapping
      #   - A copilot enterpriseTeam with direct memberships or no EnterpriseTeam at all are both okay
      sig { returns(T::Boolean) }
      def eligible_to_migrate_to_enterprise_teams?
        return false unless business_object.feature_enabled?(:enterprise_teams_migrate_from_cfb)

        permitted = T.let(true, T::Boolean)
        business_object.organizations.find_each do |org|
          unless org.permit_deletion?
            permitted = false
            break
          end
        end
        permitted
      end

      sig { returns(T::Boolean) }
      def migrate_to_enterprise_teams
        return false unless eligible_to_migrate_to_enterprise_teams?

        # Enable the unaffiliated_user_accounts feature to ensure users are not removed when the organizations
        # are and they are no longer a member of any organization in the enterprise
        GitHub.flipper[:unaffiliated_user_accounts].enable(business_object)

        # Copilot for Enterprise & Copilot for Business all manage Copilot access through organizations.
        # Migrate each Copilot enabled organization to the Enterprise Team
        business_object.organizations.find_each do |organization|
          copilot_organization = Copilot::Organization.new(organization)
          if copilot_organization.copilot_enabled? && !copilot_organization.seat_management_disabled?
            return false unless copilot_organization.migrate_to_enterprise_teams
          end

          organization.async_destroy(site_admin_deletion: true)
        end

        true
      end

      sig { returns(Numeric) }
      def number_of_enterprise_organizations
        copilot_organizations.each.count(&:copilot_plan_enterprise?)
      end

      sig { params(config_name: String, value: String, send_email: T::Boolean).void }
      def update_configuration!(config_name, value, send_email: true)
        return if value == "no_policy" && is_standalone_business?
        # don't try to update if not a valid enum value
        return unless Copilot::Configuration.defined_enums[config_name][value]
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(config_name => value)
        end

        propagate_organization_settings!(send_email ? config_name.to_sym : :noop)

        GitHub.dogstats.increment(
          "copilot.settings.#{config_name}_#{value}",
          tags: ["type:business"],
        )
      end

      private

      sig { override.returns(T::Hash[Symbol, T.any(Integer, Symbol)]) }
      def configuration_defaults
        {
          public_code_suggestions: :blocked,
          chat_enabled: copilot_standalone? ? :unconfigured : :enabled,
          mobile_chat: :enabled,
          dotcom_chat: :enabled,
          bing_github_chat: :no_policy,
          beta_features_github_chat: :disabled,
          user_feedback_opt_in: :enabled,
          user_telemetry: :disabled,
          custom_models: :unconfigured,
          cli: copilot_standalone? ? :disabled : :enabled,
          editor_preview_features: :unconfigured,
          a_chat: :unconfigured,
          a_f: :unconfigured,
          g_chat: :unconfigured,
          o1: :unconfigured,
          o3: :unconfigured,
          o_ff: :unconfigured,
          o_f: :unconfigured,
          github_enterprise_feature_group: :enabled,
          pr_summarizations: :enabled,
          max_seats: 1000,
          usage_telemetry_api: :disabled,
          copilot_plan: :business,
          copilot_extensions: :unconfigured,
          copilot_enabled: copilot_standalone? || !GitHub.flipper[:copilot_enabled_unconfigured].enabled? ? :disabled : :unconfigured,
          desktop: :enabled,
          overages: :unconfigured,
        }
      end

      # Enables Copilot for the given organizations and sends an email to each
      # organization admin notifying them of the next steps. Organizations that
      # are already enabled do not receive an email.
      sig { params(copilot_orgs: T::Array[Copilot::Organization], actor: T.nilable(::User)).void }
      def enable_and_notify_organizations(copilot_orgs, actor = nil)
        copilot_orgs.each do |copilot_org|
          propagate_settings_for_org!(copilot_org)

          next if copilot_org.copilot_enabled?

          copilot_org.enable_copilot!(actor)

          if copilot_plan_enterprise?
            CopilotEnterpriseMailer.welcome_org_admins(copilot_org.organization_object).deliver_later
          else
            CopilotForBusinessMailer.cfb_enabled_by_business(
              business_object,
              copilot_org.organization_object,
            ).deliver_later
          end
        end
      end
    end
  end
end
