# typed: strict
# frozen_string_literal: true

# PLEASE KEEP THESE SIGNATURES ALPHABETIZED BECAUSE IT MAKES
# PATRICK CRY WHEN THEY AREN'T
module Copilot
  module Organizations
    module Signatures
      extend T::Helpers

      include Copilot::Signatures::Shared

      abstract!

      sig { abstract.void }
      def beta_features_github_chat_disabled!; end

      sig { abstract.void }
      def beta_features_github_chat_enabled!; end

      sig { abstract.void }
      def bing_github_chat_disabled!; end

      sig { abstract.void }
      def bing_github_chat_enabled!; end

      sig { abstract.returns(T.nilable(Copilot::BusinessTrial)) }
      def business_trial; end

      sig { abstract.returns(T::Boolean) }
      def chat_enabled_configured?; end

      sig { abstract.returns(Symbol) }
      def copilot_beta_features_opt_in_setting; end

      sig { abstract.returns(T.nilable(Copilot::Business)) }
      def copilot_business; end

      sig { abstract.returns(String) }
      def copilot_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_cli_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_desktop_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_editor_preview_features_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_automatic_code_review_setting; end

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

      sig { abstract.returns(T::Boolean) }
      def copilot_configuration_setting_enabled?; end

      sig { abstract.returns(Symbol) }
      def copilot_custom_models_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_disabled?; end

      sig { abstract.returns(Symbol) }
      def copilot_editor_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_enabled_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_enabled?; end

      sig { abstract.returns(String) }
      def copilot_enablement_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_extensions_policy_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_business_free?; end

      sig { abstract.returns(Symbol) }
      def copilot_github_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_github_chat_bing_access_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_mobile_chat_setting; end

      sig { abstract.returns(T::Hash[Symbol, Symbol]) }
      def copilot_organization_settings; end

      sig { abstract.void }
      def copilot_plan_downgrade!; end

      sig { abstract.returns(Symbol) }
      def copilot_pr_summarizations_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_private_docs_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_snippy_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_usage_telemetry_api_setting; end

      sig { abstract.returns(T.nilable(::Customer)) }
      def customer; end

      sig { abstract.params(actor: T.nilable(::User)).void }
      def disable_copilot!(actor); end

      sig { abstract.void }
      def telemetry_aggregation_disabled!; end

      sig { abstract.params(actor: T.nilable(::User)).void }
      def enable_copilot!(actor); end

      sig { abstract.void }
      def telemetry_aggregation_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def ghec?; end

      sig { abstract.returns(T::Boolean) }
      def has_assigned_seats?; end

      sig { abstract.returns(T::Boolean) }
      def has_copilot_for_business?; end

      sig { abstract.params(assignable: T.any(::User, ::Team)).returns(T.nilable(Time)) }
      def last_token_activity(assignable); end

      sig { abstract.returns(T::Boolean) }
      def mobile_chat_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def no_chat_policy?; end

      sig { abstract.returns(T::Boolean) }
      def no_public_code_suggestions_policy?; end

      sig { abstract.returns(T::Boolean) }
      def on_free_trial?; end

      sig { abstract.returns(::Organization) }
      def organization_object; end

      sig { abstract.returns(T.nilable(Copilot::SeatAssignment)) }
      def organization_seat_assignment; end

      sig { abstract.returns(ActiveSupport::TimeWithZone) }
      def pending_cancellation_date; end

      sig { abstract.returns(T::Boolean) }
      def pending_free_trial?; end

      sig { abstract.returns([Integer, Integer]) }
      def public_code_suggestions_sorting; end

      sig { abstract.params(assigning_user: T.nilable(::User)).void }
      def seat_management_allow_all!(assigning_user); end

      sig { abstract.params(assigning_user: T.nilable(::User)).void }
      def seat_management_disable!(assigning_user); end

      sig { abstract.returns(T::Boolean) }
      def seat_management_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def seat_management_enabled_for_all?; end

      sig { abstract.returns(T::Boolean) }
      def seat_management_enabled_for_selected?; end

      sig { abstract.params(keep_assignments: T::Boolean).void }
      def seat_management_selected_teams_and_users!(keep_assignments: false); end

      sig { abstract.returns(String) }
      def seat_management_setting; end

      sig { abstract.returns(T::Boolean) }
      def show_csv_exports?; end

      sig { abstract.returns(T::Boolean) }
      def telemetry_aggregation_enabled?; end

      sig { abstract.returns(T.nilable(String)) }
      def to_csv; end

      sig { abstract.returns(Symbol) }
      def copilot_user_feedback_opt_in_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_overages_setting; end
    end
  end
end
