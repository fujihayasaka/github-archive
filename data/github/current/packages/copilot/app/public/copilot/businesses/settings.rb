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

      include Copilot::Businesses::Settings::Models
      include Copilot::Businesses::Settings::McpRegistries
      include Copilot::Businesses::Settings::Policies
      include GitHub::Memoizer

      abstract!

      include HasConfiguration

      delegate :copilot_for_dotcom, :copilot_for_dotcom_unconfigured?, :copilot_for_dotcom_configured?, :copilot_for_dotcom_enabled?,
               :copilot_for_dotcom_disabled?, :copilot_for_dotcom_no_policy?, :copilot_for_dotcom_chat_enabled?, :copilot_for_dotcom_setting,
               :mobile_chat,
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
               :beta_features_github_chat,
               :private_telemetry, :private_telemetry_unconfigured?, :private_telemetry_configured?,
               :private_telemetry_enabled?, :private_telemetry_disabled?, :private_telemetry_no_policy?,
               :editor_preview_features, :editor_preview_features_unconfigured?, :editor_preview_features_configured?, :editor_preview_features_enabled?, :editor_preview_features_disabled?, :editor_preview_features_no_policy?,
               :agent_mode, :agent_mode_unconfigured?, :agent_mode_configured?, :agent_mode_enabled?, :agent_mode_disabled?, :agent_mode_no_policy?,
               :automatic_code_review, :automatic_code_review_unconfigured?, :automatic_code_review_configured?, :automatic_code_review_enabled?, :automatic_code_review_disabled?, :automatic_code_review_no_policy?,
               :a_f, :a_f_unconfigured?, :a_f_configured?, :a_f_enabled?, :a_f_disabled?, :a_f_no_policy?,
               :afos, :afos_unconfigured?, :afos_configured?, :afos_enabled?, :afos_disabled?, :afos_no_policy?,
               :al, :al_unconfigured?, :al_enabled?, :al_disabled?, :al_no_policy?,
               :g_tf, :g_tf_unconfigured?, :g_tf_enabled?, :g_tf_disabled?, :g_tf_no_policy?,
               :o1, :o1_unconfigured?, :o1_configured?, :o1_enabled?, :o1_disabled?, :o1_no_policy?,
               :o_ff, :o_ff_unconfigured?, :o_ff_configured?, :o_ff_enabled?, :o_ff_disabled?, :o_ff_no_policy?,
               :o_fm, :o_fm_unconfigured?, :o_fm_enabled?, :o_fm_disabled?, :o_fm_no_policy?,
               :o_f, :o_f_unconfigured?, :o_f_configured?, :o_f_enabled?, :o_f_disabled?, :o_f_no_policy?,
               :o_t, :o_t_unconfigured?, :o_t_enabled?, :o_t_disabled?, :o_t_no_policy?,
               :workspace_for_emu, :workspace_for_emu_disabled?, :workspace_for_emu_enabled?,
               :overages, :overages_unconfigured?, :overages_configured?, :overages_enabled?, :overages_disabled?, :overages_no_policy?,
               :swe_agent, :swe_agent_unconfigured?, :swe_agent_disabled?, :swe_agent_enabled?, :swe_agent_no_policy?,
               :mcp, :mcp_enabled?, :mcp_disabled?, :mcp_no_policy?, :mcp_unconfigured?,
               :spark, :spark_enabled?, :spark_disabled?, :spark_no_policy?,
               :public_code_suggestions,
               :insights, :insights_enabled?, :insights_disabled?, :insights_no_policy?, :insights_unconfigured?,
               :code_review, :code_review_enabled?, :code_review_disabled?, :code_review_no_policy?, :code_review_unconfigured?,
               :code_review_beta_features,
               to: :configuration

      # Please don't add more aliases unless you need it.

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
        business_object.feature_flag_enabled_or_raise?(:copilot_for_business_free) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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
        business_org_ids = business_object.organization_ids
        return 0 if copilot_disabled? || business_org_ids.empty?

        Copilot::Configuration.batched_scope(:configurable_id, values: business_org_ids) do |scope|
          unless copilot_enabled_for_all_organizations?
            scope = scope.where(copilot_enabled: "enabled")
          end
          scope.where(configurable_type: "Organization")
        end.count
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

      # Disable Copilot for all organizations in this business, and
      # sends an email to each organization admin notifying them of the next
      # steps. This does not disable Copilot for the business itself or
      # enterprise-assigned users or enterprise teams.
      sig { override.params(actor: T.nilable(::User)).void }
      def disable_copilot_for_all_organizations!(actor = nil)
        disable_and_notify_organizations(copilot_organizations, actor)

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.organizations_disabled!
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_disabled_for_all_organizations?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.organizations_disabled?
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

      sig { returns(T::Boolean) }
      memoize def any_org_on_enterprise_plan?
        copilot_organizations.any?(&:copilot_plan_enterprise?)
      end

      sig { returns(T::Boolean) }
      def can_access_copilot_enterprise_models?
        return true if any_org_on_enterprise_plan?
        return false if copilot_standalone?

        configuration.copilot_plan_enterprise?
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

      sig { override.returns(String) }
      def ea_user_fallback_policy_setting
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.ea_user_fallback_policy
        end
      end

      sig { override.void }
      def ea_user_fallback_policy_disabled!
        update_configuration!("ea_user_fallback_policy", "disabled", send_email: false)
      end

      sig { override.returns(T::Boolean) }
      def ea_user_fallback_policy_disabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.ea_user_fallback_policy_disabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def ea_user_fallback_policy_enabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.ea_user_fallback_policy_enabled?
        end
      end

      sig { override.void }
      def ea_user_fallback_policy_enabled!
        update_configuration!("ea_user_fallback_policy", "enabled", send_email: false)
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

      sig { returns(T::Boolean) }
      def code_review_simultaneous_writes_enabled?
        business_object.feature_flag_enabled?(:ccr_policy_simultaneous_writes, default: false) && !business_object.feature_flag_enabled?(:copilot_code_review_policy, default: false)
      end

      sig { override.void }
      def beta_features_github_chat_no_policy!
        update_configuration!("beta_features_github_chat", "no_policy", send_email: false)

        if code_review_simultaneous_writes_enabled?
          code_review_beta_features_no_policy!
        end
      end

      sig { override.void }
      def beta_features_github_chat_disabled!
        update_configuration!("beta_features_github_chat", "disabled", send_email: false)

        if code_review_simultaneous_writes_enabled?
          code_review_beta_features_disabled!
        end
      end

      sig { override.void }
      def beta_features_github_chat_enabled!
        update_configuration!("beta_features_github_chat", "enabled", send_email: false)

        if code_review_simultaneous_writes_enabled?
          code_review_beta_features_enabled!
        end
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

        if code_review_simultaneous_writes_enabled?
          code_review_disabled!
        end
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

        if code_review_simultaneous_writes_enabled?
          code_review_enabled!
        end
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

        if code_review_simultaneous_writes_enabled?
          code_review_no_policy!
        end
      end

      sig { override.void }
      def mobile_chat_disabled!
        update_configuration!("mobile_chat", "disabled", send_email: true)
      end

      sig { override.void }
      def mobile_chat_enabled!
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
        !configurable_object.feature_flag_enabled_or_raise?(:copilot_for_business_free) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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

      sig { override.params(feature: ::Symbol).void }
      def propagate_organization_settings!(feature = :noop)
        # call propagate_settings_for_org! for each organization in biz
        Copilot::BatchUpdateOrgSettingsJob.perform_later(business_object.id, feature)
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

        unless copilot_org.feature_flag_enabled?(:copilot_desktop_business_refactor, default: false)
          if desktop_disabled?
            copilot_org.desktop_disabled!(feature == :desktop)
          end

          if desktop_enabled?
            copilot_org.desktop_enabled!(feature == :desktop)
          end
        end

        if editor_preview_features_disabled?
          copilot_org.editor_preview_features_disabled!(force: true)
        end

        if editor_preview_features_enabled?
          copilot_org.editor_preview_features_enabled!(force: true)
        end

        if agent_mode_disabled?
          copilot_org.agent_mode_disabled!(force: true)
        end

        if agent_mode_enabled?
          copilot_org.agent_mode_enabled!(force: true)
        end

        if automatic_code_review_disabled?
          copilot_org.automatic_code_review_disabled!(force: true)
        end

        if automatic_code_review_enabled?
          copilot_org.automatic_code_review_enabled!(force: true)
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

        if afos_disabled?
          copilot_org.afos_disabled!(force: true)
        end

        if afos_enabled?
          copilot_org.afos_enabled!(force: true)
        end

        if al_disabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.al_disabled!(force: true)
        end

        if al_enabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.al_enabled!(force: true)
        end

        if aofo_disabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.aofo_disabled!(force: true)
        end

        if aofo_enabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.aofo_enabled!(force: true)
        end

        if g_chat_disabled?
          copilot_org.g_chat_disabled!(force: true)
        end

        if g_chat_enabled?
          copilot_org.g_chat_enabled!(force: true)
        end

        if g_tf_disabled?
          copilot_org.g_tf_disabled!(force: true)
        end

        if g_tf_enabled?
          copilot_org.g_tf_enabled!(force: true)
        end

        if gtff_disabled?
          copilot_org.gtff_disabled!(force: true)
        end

        if gtff_enabled?
          copilot_org.gtff_enabled!(force: true)
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

        if o_ff_disabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.o_ff_disabled!(force: true)
        end

        if o_ff_enabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.o_ff_enabled!(force: true)
        end

        if o_fm_disabled?
          copilot_org.o_fm_disabled!(force: true)
        end

        if o_fm_enabled?
          copilot_org.o_fm_enabled!(force: true)
        end

        if o_f_disabled?
          copilot_org.o_f_disabled!(force: true)
        end

        if o_f_enabled?
          copilot_org.o_f_enabled!(force: true)
        end

        # only disable setting if org is on the enterprise plan
        if o_t_disabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.o_t_disabled!(force: true)
        end

        # only enable setting if orgs that are on the enterprise plan
        if o_t_enabled? && copilot_org.copilot_plan_enterprise?
          copilot_org.o_t_enabled!(force: true)
        end

        if obmb_disabled?
          copilot_org.obmb_disabled!(force: true)
        end

        if obmb_enabled?
          copilot_org.obmb_enabled!(force: true)
        end

        if obmw_disabled?
          copilot_org.obmw_disabled!(force: true)
        end

        if obmw_enabled?
          copilot_org.obmw_enabled!(force: true)
        end

        if ofct_disabled?
          copilot_org.ofct_disabled!(force: true)
        end

        if ofct_enabled?
          copilot_org.ofct_enabled!(force: true)
        end

        if ofo_disabled?
          copilot_org.ofo_disabled!(force: true)
        end

        if ofo_enabled?
          copilot_org.ofo_enabled!(force: true)
        end

        if grok_code_disabled?
          copilot_org.grok_code_disabled!(force: true)
        end

        if grok_code_enabled?
          copilot_org.grok_code_enabled!(force: true)
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
          copilot_org.mobile_chat_disabled!(feature == :mobile_chat)
        end

        if mobile_chat_enabled?
          copilot_org.mobile_chat_enabled!(feature == :mobile_chat)
        end

        if copilot_extensions_disabled?
          copilot_org.copilot_extensions_disabled!
        end

        if copilot_extensions_enabled?
          copilot_org.copilot_extensions_enabled!
        end

        if bing_github_chat_enabled?
          copilot_org.bing_github_chat_enabled!(force: true)
        end

        if bing_github_chat_disabled?
          copilot_org.bing_github_chat_disabled!(force: true)
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
          copilot_org.beta_features_github_chat_enabled!(force: true)
        end

        if beta_features_github_chat_disabled?
          copilot_org.beta_features_github_chat_disabled!(force: true)
        end

        if overages_disabled?
          copilot_org.force_overages_disabled!
        end

        if overages_enabled?
          copilot_org.force_overages_enabled!
        end

        if swe_agent_disabled?
          copilot_org.swe_agent_disabled!(force: true, send_email: feature == :swe_agent)
        end

        if swe_agent_enabled?
          copilot_org.swe_agent_enabled!(force: true, send_email: feature == :swe_agent)
        end

        if mcp_disabled?
          copilot_org.mcp_disabled!(force: true)
        end

        if mcp_enabled?
          copilot_org.mcp_enabled!(force: true)
        end

        if spark_disabled?
          copilot_org.spark_disabled!(force: true, send_email: feature == :spark)
        end

        if spark_enabled?
          copilot_org.spark_enabled!(force: true, send_email: feature == :spark)
        end

        if insights_disabled?
          copilot_org.insights_disabled!(force: true)
        end

        if insights_enabled?
          copilot_org.insights_enabled!(force: true)
        end

        if business_object.feature_flag_enabled_or_raise?(:copilot_code_review_policy) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          if code_review_disabled?
            copilot_org.code_review_disabled!(force: true, send_email: feature == :code_review)
          end

          if code_review_enabled?
            copilot_org.code_review_enabled!(force: true, send_email: feature == :code_review)
          end

          if code_review_beta_features_disabled?
            copilot_org.code_review_beta_features_disabled!(force: true)
          end

          if code_review_beta_features_enabled?
            copilot_org.code_review_beta_features_enabled!(force: true)
          end
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
      def agent_mode_enabled!
        update_configuration!("agent_mode", "enabled", send_email: true)
      end

      sig { override.void }
      def agent_mode_disabled!
        update_configuration!("agent_mode", "disabled", send_email: true)
      end

      sig { override.void }
      def agent_mode_no_policy!
        update_configuration!("agent_mode", "no_policy", send_email: false)
      end

      sig { override.void }
      def automatic_code_review_enabled!
        update_configuration!("automatic_code_review", "enabled", send_email: true)
      end

      sig { override.void }
      def automatic_code_review_disabled!
        update_configuration!("automatic_code_review", "disabled", send_email: true)
      end

      sig { override.void }
      def automatic_code_review_no_policy!
        update_configuration!("automatic_code_review", "no_policy", send_email: false)
      end

      sig { override.void }
      def o_f_disabled!
        update_configuration!("o_f", "disabled", send_email: true)
      end

      sig { override.void }
      def g_tf_enabled!
        update_configuration!("g_tf", "enabled", send_email: false)
      end

      sig { override.void }
      def g_tf_disabled!
        update_configuration!("g_tf", "disabled", send_email: false)
      end

      sig { override.void }
      def g_tf_no_policy!
        update_configuration!("g_tf", "no_policy", send_email: false)
      end

      sig { override.void }
      def o_fm_enabled!
        update_configuration!("o_fm", "enabled", send_email: false)
      end

      sig { override.void }
      def o_fm_disabled!
        update_configuration!("o_fm", "disabled", send_email: false)
      end

      sig { override.void }
      def o_fm_no_policy!
        update_configuration!("o_fm", "no_policy", send_email: false)
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
      def afos_enabled!
        update_configuration!("afos", "enabled", send_email: false)
      end

      sig { override.void }
      def afos_disabled!
        update_configuration!("afos", "disabled", send_email: false)
      end

      sig { override.void }
      def afos_no_policy!
        update_configuration!("afos", "no_policy", send_email: false)
      end

      sig { override.void }
      def al_enabled!
        update_configuration!("al", "enabled", send_email: false)
      end

      sig { override.void }
      def al_disabled!
        update_configuration!("al", "disabled", send_email: false)
      end

      sig { override.void }
      def al_no_policy!
        update_configuration!("al", "no_policy", send_email: false)
      end

      sig { returns(T::Boolean) }
      def should_render_o_ff?
        return false if business_object.feature_flag_enabled?(:copilot_o_ff_policy_deprecated, default: false)

        true
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

      sig { override.void }
      def o_t_enabled!
        update_configuration!("o_t", "enabled", send_email: false)
      end

      sig { override.void }
      def o_t_disabled!
        update_configuration!("o_t", "disabled", send_email: false)
      end

      sig { override.void }
      def o_t_no_policy!
        update_configuration!("o_t", "no_policy", send_email: false)
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

      sig { override.void }
      def swe_agent_enabled!
        update_configuration!("swe_agent", "enabled", send_email: true)
      end

      sig { override.void }
      def swe_agent_disabled!
        update_configuration!("swe_agent", "disabled", send_email: true)
      end

      sig { override.void }
      def swe_agent_no_policy!
        update_configuration!("swe_agent", "no_policy", send_email: false)
      end

      sig { override.void }
      def mcp_enabled!
        update_configuration!("mcp", "enabled", send_email: false)
      end

      sig { override.void }
      def mcp_disabled!
        update_configuration!("mcp", "disabled", send_email: false)
      end

      sig { override.void }
      def mcp_no_policy!
        update_configuration!("mcp", "no_policy", send_email: false)
      end

      sig { override.void }
      def spark_enabled!
        update_configuration!("spark", "enabled", send_email: true)
      end

      sig { override.void }
      def spark_disabled!
        update_configuration!("spark", "disabled", send_email: true)
      end

      sig { override.void }
      def spark_no_policy!
        update_configuration!("spark", "no_policy", send_email: false)
      end

      sig { override.void }
      def insights_enabled!
        update_configuration!("insights", "enabled", send_email: false)
      end

      sig { override.void }
      def insights_disabled!
        update_configuration!("insights", "disabled", send_email: false)
      end

      sig { override.void }
      def insights_no_policy!
        update_configuration!("insights", "no_policy", send_email: false)
      end

      sig { override.void }
      def code_review_enabled!
        update_configuration!("code_review", "enabled", send_email: true)
      end

      sig { override.void }
      def code_review_disabled!
        update_configuration!("code_review", "disabled", send_email: true)
      end

      sig { override.void }
      def code_review_no_policy!
        update_configuration!("code_review", "no_policy", send_email: false)
      end

      sig { override.returns(T::Boolean) }
      def code_review_beta_features_enabled?
        ActiveRecord::Base.connected_to(role: :reading) do
          return false if code_review_disabled? #takes precedence

          configuration.code_review_beta_features_enabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def code_review_beta_features_disabled?
        return true if code_review_disabled? #takes precedence
        !code_review_beta_features_enabled?
      end

      sig { override.returns(T::Boolean) }
      def code_review_beta_features_no_policy?
        ActiveRecord::Base.connected_to(role: :reading) do
          return true if code_review_no_policy? #takes precedence

          configuration.code_review_beta_features_no_policy?
        end
      end

      sig { override.void }
      def code_review_beta_features_enabled!
        update_configuration!("code_review_beta_features", "enabled", send_email: false)
      end

      sig { override.void }
      def code_review_beta_features_disabled!
        update_configuration!("code_review_beta_features", "disabled", send_email: false)
      end

      sig { override.void }
      def code_review_beta_features_no_policy!
        update_configuration!("code_review_beta_features", "no_policy", send_email: false)
      end

      sig { returns(T::Boolean) }
      def has_copilot_enterprise_access?
        return true if business_object.feature_flag_enabled_or_raise?(:copilot_for_enterprise) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        configuration.copilot_plan_enterprise?
      end

      sig { returns(T::Boolean) }
      def has_copilot_business_access?
        return true if business_object.feature_flag_enabled_or_raise?(:copilot_for_business) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

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
        return false unless business_object.feature_flag_enabled_or_raise?(:enterprise_teams_migrate_from_cfb) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

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
        FeatureFlag.vexi_management.add_feature_flag_actors(:unaffiliated_user_accounts, [business_object]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage

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
        Copilot::Configuration.where(
          configurable_id: copilot_organizations.pluck(:id),
          configurable_type: "Organization",
          copilot_plan: "enterprise"
        ).count
      end

      sig { override.params(config_name: String, value: String, send_email: T::Boolean).void }
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
          public_code_suggestions: :allowed,
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
          agent_mode: :unconfigured,
          automatic_code_review: :unconfigured,
          a_chat: :unconfigured,
          a_f: :unconfigured,
          afos: :unconfigured,
          al: :unconfigured,
          g_chat: :unconfigured,
          g_tf: :unconfigured,
          gtff: :unconfigured,
          o1: :unconfigured,
          o3: :unconfigured,
          o_ff: :unconfigured,
          obmb: :unconfigured,
          obmw: :unconfigured,
          ofct: :unconfigured,
          aofo: :unconfigured,
          ofo: :unconfigured,
          o_fm: :unconfigured,
          o_f: :unconfigured,
          o_t: :unconfigured,
          grok_code: :unconfigured,
          github_enterprise_feature_group: :enabled,
          pr_summarizations: :enabled,
          max_seats: 1000,
          usage_telemetry_api: :disabled,
          copilot_plan: :business,
          copilot_extensions: :unconfigured,
          copilot_enabled: copilot_standalone? || !FeatureFlag.vexi.enabled_or_raise?(:copilot_enabled_unconfigured) ? :disabled : :unconfigured, # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          desktop: :enabled,
          overages: :unconfigured,
          swe_agent: :unconfigured,
          mcp: :unconfigured,
          spark: :disabled,
          ea_user_fallback_policy: :disabled,
          insights: :unconfigured,
          code_review: :enabled,
          code_review_beta_features: :disabled,
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
