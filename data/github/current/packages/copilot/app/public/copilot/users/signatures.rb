# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# PLEASE KEEP THESE SIGNATURES ALPHABETIZED BECAUSE IT MAKES
# PATRICK CRY WHEN THEY AREN'T
# I AM BEGGING YOU PLEASE
module Copilot
  module Users
    module Signatures
      extend T::Helpers

      include Copilot::Signatures::Shared

      CopilotQuotaDetail = T.type_alias do
        {
          feature: String,
          percentage: Float,
          quota: Integer,
        }
      end

      CopilotUserDetails = T.type_alias do
        {
          copilot_user_settings: T::Hash[Symbol, Symbol],
          subscription_plan: Symbol,
          is_trial: T::Boolean,
          is_technical_preview_user: T::Boolean,
          free_access_type: Symbol,
          trust_tier: T.nilable(Symbol)
        }
      end

      QuotaSnapshot = T.type_alias do
        {
          quota_id: String,
          entitlement: Integer,
          remaining: Integer,
          unlimited: T::Boolean,
          overage_count: Integer,
          overage_permitted: T::Boolean,
          percent_remaining: Float,
        }
      end

      abstract!

      sig { abstract.returns(Symbol) }
      def access_type; end

      sig { abstract.returns(String) }
      def access_type_sku; end

      sig { abstract.params(actor: ::User, reason: String).returns(T.nilable(Copilot::AdministrativeBlock)) }
      def administrative_block!(actor, reason); end

      sig { abstract.returns(T::Boolean) }
      def administrative_blocked?; end

      sig { abstract.params(actor: ::User, reason: String).void }
      def administrative_unblock!(actor, reason); end

      sig { abstract.returns(T::Array[::Billing::SubscriptionItem]) }
      def all_copilot_subscription_items; end

      sig { abstract.returns(Promise[::Billing::SubscriptionItem]) }
      def async_copilot_active_subscription_item; end

      sig { abstract.returns(Promise[T::Boolean]) }
      def async_is_technical_preview_user?; end

      sig { abstract.returns(Promise[T::Array[Copilot::Organization]]) }
      def async_orgs_using_copilot_for_business; end

      sig { abstract.returns(Promise[T::Array[Copilot::SeatAssignment]]) }
      def async_seat_assignments; end

      sig { abstract.returns(Promise[T::Array[Copilot::Seat]]) }
      def async_seats; end

      sig { abstract.returns(Promise[T.nilable(Copilot::TechnicalPreviewUser)]) }
      def async_technical_preview_user; end

      sig { abstract.returns(ActiveSupport::Duration) }
      def available_trial_length; end

      sig { abstract.returns(T::Boolean) }
      def can_modify_copilot_settings?; end

      sig { abstract.returns(T::Boolean) }
      def can_signup_for_free?; end

      sig { abstract.returns(T::Boolean) }
      def can_signup_for_limited?; end

      sig { abstract.returns(T::Boolean) }
      def can_view_copilot_settings?; end

      sig { abstract.returns(T.nilable(Copilot::Notifications::NotificationBase)) }
      def check_notifications; end

      sig { abstract.returns(String) }
      def codespaces_demo_key; end

      sig { abstract.returns(T::Boolean) }
      def codespaces_demo_request_allowed?; end

      sig { abstract.returns(T::Boolean) }
      def codespaces_demo_session_active?; end

      sig { abstract.returns(T.nilable(String)) }
      def codespaces_demo_session_value; end

      sig { abstract.params(codespace: Codespace).returns(T::Boolean) }
      def codespaces_demo_usage_allowed?(codespace); end

      sig do
        abstract.type_parameters(:A).params(
          name: String,
          tags: T::Hash[Symbol, String],
          block: T.proc.returns(T.type_parameter(:A)),
        ).returns(T.type_parameter(:A))
      end
      def collect_metrics(name, **tags, &block); end

      sig { abstract.returns(T::Boolean) }
      def consumptive_user?; end

      sig { abstract.returns(T.nilable(::Billing::Public::SubscriptionItem)) }
      def copilot_active_subscription_item; end

      sig { abstract.returns(Copilot::Authorizer) }
      def copilot_authorizer_object_no_snippy; end

      sig { abstract.returns(Copilot::Authorizer) }
      def copilot_authorizer_object; end

      sig { abstract.returns(Symbol) }
      def copilot_automatic_code_review_setting; end

      sig { abstract.returns(T.nilable(Copilot::Business)) }
      def copilot_business; end

      sig { abstract.returns(T::Array[Copilot::Business]) }
      def copilot_businesses; end

      sig { abstract.returns(Symbol) }
      def copilot_cli_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_desktop_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_editor_preview_features_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_a_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_a_f_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_g_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_o1_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_o3_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_o_ff_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_o_f_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_custom_models_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_editor_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_extensions_policy_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_business_free?; end

      sig { abstract.returns(Symbol) }
      def copilot_free_user_type; end

      sig { abstract.returns(Symbol) }
      def copilot_github_chat_bing_access_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_github_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_mobile_chat_setting; end

      sig { abstract.returns(T.nilable(Copilot::Organization)) }
      def copilot_organization; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def copilot_organizations; end

      sig { abstract.returns(T.nilable(T.any(Copilot::Organization, Copilot::Business))) }
      def copilot_provider; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def copilot_enterprise_organizations; end

      sig { abstract.returns(Symbol) }
      def copilot_pr_summarizations_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_private_docs_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_snippy_setting; end

      sig { abstract.returns(T.nilable(T::Array[Copilot::Business])) }
      def copilot_standalone_businesses; end

      sig { abstract.returns(Symbol) }
      def copilot_subscription_plan; end

      sig { abstract.returns(Symbol) }
      def copilot_telemetry_configuration; end

      sig { abstract.returns(CopilotUserDetails) }
      def copilot_user_details; end

      sig { abstract.returns(Copilot::User) }
      def copilot_user_object; end

      sig { abstract.returns(T::Hash[Symbol, Symbol]) }
      def copilot_user_settings; end

      sig { abstract.returns(T::Boolean) }
      def copilot_content_exclusion_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def copilot_code_review_enabled?; end

      sig { abstract.params(repository: Repository).returns(T::Boolean) }
      def copilot_coding_guidelines_enabled?(repository); end

      sig { abstract.void }
      def dashboard_entry_point_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def dashboard_entry_point_enabled?; end

      sig { abstract.void }
      def dashboard_entry_point_enabled!; end

      sig { abstract.void }
      def show_copilot_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def show_copilot_enabled?; end

      sig { abstract.void }
      def show_copilot_enabled!; end

      sig { abstract.returns(Integer) }
      def days_left_on_trial; end

      sig { abstract.returns(Integer) }
      def days_until_next_billing_date; end

      sig { abstract.returns(T::Boolean) }
      def disabled?; end

      sig { abstract.returns(T::Boolean) }
      def dunning?; end

      sig { abstract.returns(T::Boolean) }
      def eligible_for_trial?; end

      sig { abstract.returns(String) }
      def free_signup_reason; end

      sig { abstract.void }
      def free_user_block!; end

      sig { abstract.returns(T::Boolean) }
      def free_user_blocked?; end

      sig { abstract.void }
      def free_user_unblock!; end

      sig { abstract.returns(T::Boolean) }
      def has_active_monthly_subscription?; end

      sig { abstract.returns(T::Boolean) }
      def has_active_subscription?; end

      sig { abstract.returns(T::Boolean) }
      def has_active_yearly_subscription?; end

      sig { abstract.returns(T::Boolean) }
      def has_been_warned?; end

      sig { abstract.returns(T::Boolean) }
      def has_cfb_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_cfe_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_cfi_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_cfi_pro_plus_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_cb_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_ce_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_completions_quota_remaining?; end

      sig { abstract.returns(T::Boolean) }
      def has_chat_quota_remaining?; end

      sig { abstract.returns(T::Boolean) }
      def has_ci_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_copilot_standalone_business?; end

      sig { abstract.returns(T::Boolean) }
      def has_free_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_limited_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_multi_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_paid_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_pro_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_pro_plus_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_signed_up?; end

      sig { abstract.returns(T::Boolean) }
      def has_subscription_ended?; end

      sig { abstract.returns(T::Boolean) }
      def has_trial_organization?; end

      sig { abstract.returns(T::Boolean) }
      def has_trial_subscription?; end

      sig { abstract.void }
      def increment_codespaces_demo_session_value!; end

      sig { abstract.returns(T::Boolean) }
      def is_partner_user?; end

      sig { abstract.returns(T::Boolean) }
      def is_technical_preview_user?; end

      sig { abstract.returns(T.nilable(Copilot::AggregateUsageDetail)) }
      def latest_usage_detail; end

      sig { abstract.returns(T.nilable(Copilot::LimitedUser)) }
      def limited_user; end

      sig { abstract.returns(T::Boolean) }
      def editor_preview_features_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def automatic_code_review_enabled?; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def orgs_having_copilot_for_business; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def orgs_using_copilot_for_business; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def partner_orgs; end

      sig { abstract.returns(T::Array[CopilotQuotaDetail]) }
      def quota_details; end

      sig { abstract.params(feature: String).returns(Float) }
      def quota_percentage_remaining(feature:); end # chat/completions/etc

      sig { abstract.params(feature: String).returns(Float) }
      def quota_feature_entitlement(feature:); end # chat/completions/etc

      sig { abstract.params(feature: String).returns(Float) }
      def quota_feature_overage_count(feature:); end # chat/completions/etc

      sig { abstract.returns(T::Hash[String, QuotaSnapshot]) }
      def quota_snapshots; end

      sig { abstract.returns(Date) }
      def quota_reset_date; end

      sig { abstract.returns(T::Boolean) }
      def spammy?; end

      sig { abstract.returns(T::Boolean) }
      def spark_enabled?; end

      sig { abstract.returns(GitHub::Result) }
      def subscribe_free_user; end

      sig { abstract.returns(GitHub::Result) }
      def subscribe_limited_user; end

      sig { abstract.params(duration: Symbol).returns(GitHub::Result) }
      def subscribe(duration); end

      sig { abstract.returns(T::Boolean) }
      def subscription_ended_due_to_billing_trouble?; end

      sig { abstract.returns(Symbol) }
      def subscription_type; end

      sig { abstract.returns(T::Boolean) }
      def technical_preview_user_lost_access?; end

      sig { abstract.returns(T.nilable(Copilot::TechnicalPreviewUser)) }
      def technical_preview_user; end

      sig { abstract.returns(T::Boolean) }
      def telemetry_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def telemetry_required?; end

      sig { abstract.returns(Copilot::TelemetrySnapshot) }
      def telemetry_snapshot; end

      sig { abstract.returns(T.nilable(String)) }
      def telemetry_snapshot_id; end

      sig { abstract.returns(String) }
      def telemetry_setting; end

      sig { abstract.returns(T::Boolean) }
      def trade_restricted?; end

      sig { abstract.returns(T::Boolean) }
      def trial_only_subscription?; end

      sig { abstract.returns(::User) }
      def user_object; end

      sig { abstract.params(actor: ::User, reference_number: String, reason: String).returns(Copilot::AdministrativeBlock) }
      def warn_user!(actor, reference_number, reason); end

      sig { abstract.returns(T::Boolean) }
      def workspace_enabled?; end

      sig { abstract.returns(Symbol) }
      def copilot_overages_setting; end
    end
  end
end
