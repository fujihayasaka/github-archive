# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# PLEASE KEEP THESE SIGNATURES ALPHABETIZED BECAUSE IT MAKES
# PATRICK CRY WHEN THEY AREN'T
# I AM BEGGING YOU PLEASE
module Copilot
  module Users
    module Signatures
      extend T::Helpers
      extend T::Sig

      include Copilot::Signatures::Shared

      CopilotUserSettings = T.type_alias do
        {
          cli_setting: Symbol,
          copilot_extensions_setting: Symbol,
          custom_models_setting: Symbol,
          editor_chat_setting: Symbol,
          github_chat_setting: Symbol,
          mobile_chat_setting: Symbol,
          pr_summarizations_setting: Symbol,
          private_docs_setting: Symbol,
          snippy_setting: Symbol,
          telemetry_configuration: Symbol,
        }
      end

      CopilotUserDetails = T.type_alias do
        {
          copilot_user_settings: CopilotUserSettings,
          subscription_plan: Symbol,
          is_trial: T::Boolean,
          is_technical_preview_user: T::Boolean,
          free_access_type: Symbol,
          trust_tier: T.nilable(Symbol)
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

      sig { abstract.returns(T.nilable(::Billing::Public::SubscriptionItem)) }
      def copilot_active_subscription_item; end

      sig { abstract.returns(Copilot::Authorizer) }
      def copilot_authorizer_object_no_snippy; end

      sig { abstract.returns(Copilot::Authorizer) }
      def copilot_authorizer_object; end

      sig { abstract.returns(T.nilable(Copilot::Business)) }
      def copilot_business; end

      sig { abstract.returns(T::Array[Copilot::Business]) }
      def copilot_businesses; end

      sig { abstract.returns(Symbol) }
      def copilot_cli_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_custom_models_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_editor_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_extensions_policy_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_free_user_type; end

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

      sig { abstract.returns(CopilotUserSettings) }
      def copilot_user_settings; end

      sig { abstract.returns(T::Boolean) }
      def copilot_content_exclusion_enabled?; end

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
      def has_copilot_standalone_business?; end

      sig { abstract.returns(T::Boolean) }
      def has_free_access?; end

      sig { abstract.returns(T::Boolean) }
      def has_paid_access?; end

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

      sig { abstract.returns(T::Boolean) }
      def nes_enabled?; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def orgs_having_copilot_for_business; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def orgs_using_copilot_for_business; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def partner_orgs; end

      sig { abstract.returns(T::Boolean) }
      def spammy?; end

      sig { abstract.returns(GitHub::Result) }
      def subscribe_free_user; end

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
    end
  end
end
