# typed: strict
# frozen_string_literal: true

# PLEASE KEEP THESE SIGNATURES ALPHABETIZED BECAUSE IT MAKES
# PATRICK CRY WHEN THEY AREN'T
module Copilot
  module Businesses
    module Signatures
      extend T::Helpers
      extend T::Sig

      abstract!

      include Copilot::Signatures::Shared

      sig { abstract.void }
      def beta_features_github_chat_disable!; end

      sig { abstract.void }
      def beta_features_github_chat_enable!; end

      sig { abstract.returns(T::Boolean) }
      def beta_features_github_chat_no_policy?; end

      sig { abstract.void }
      def beta_features_github_chat_no_policy!; end

      sig { abstract.void }
      def bing_github_chat_disable!; end

      sig { abstract.void }
      def bing_github_chat_enable!; end

      sig { abstract.returns(T::Boolean) }
      def bing_github_chat_no_policy?; end

      sig { abstract.void }
      def bing_github_chat_no_policy!; end

      sig { abstract.returns(::Business) }
      def business_object; end

      sig { abstract.returns(T::Boolean) }
      def chat_enabled_configured?; end

      sig { abstract.returns(Symbol) }
      def copilot_beta_features_opt_in_setting; end

      sig { abstract.returns(String) }
      def copilot_business_enablement_setting; end

      sig { abstract.returns(T::Hash[Symbol, Symbol]) }
      def copilot_business_settings; end

      sig { abstract.returns(String) }
      def copilot_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_cli_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_custom_models_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_disabled?; end

      sig { abstract.returns(Symbol) }
      def copilot_editor_chat_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def copilot_enabled_for_all_organizations?; end

      sig { abstract.returns(T::Boolean) }
      def copilot_enabled_for_selected_organizations?; end

      sig { abstract.returns(Integer) }
      def copilot_enabled_organizations_count; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def copilot_enabled_organizations; end

      sig { abstract.returns(Symbol) }
      def copilot_enabled_setting; end

      sig { abstract.void }
      def copilot_extensions_no_policy!; end

      sig { abstract.returns(Symbol) }
      def copilot_extensions_policy_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_business_free?; end

      sig { abstract.returns(Symbol) }
      def copilot_github_chat_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_github_chat_bing_access_setting; end

      sig { abstract.returns(Integer) }
      def copilot_max_seats; end

      sig { abstract.params(value: Integer).void }
      def copilot_max_seats=(value); end

      sig { abstract.returns(Symbol) }
      def copilot_mobile_chat_setting; end

      sig { abstract.returns(T::Array[Copilot::Organization]) }
      def copilot_organizations; end

      sig { abstract.void }
      def copilot_plan_downgrade!; end

      sig { abstract.returns(Symbol) }
      def copilot_pr_summarizations_setting; end

      sig { abstract.returns(Symbol) }
      def copilot_private_docs_setting; end

      sig { abstract.returns(Integer) }
      def copilot_seat_assignment_count; end

      sig { abstract.returns(T::Array[Copilot::SeatAssignment]) }
      def copilot_seat_assignments; end

      sig { abstract.returns(Integer) }
      def copilot_seat_count; end

      sig { abstract.returns(T::Array[Copilot::Seat]) }
      def copilot_seats; end

      sig { abstract.returns(Symbol) }
      def copilot_snippy_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_standalone?; end

      sig { abstract.returns(Symbol) }
      def copilot_usage_telemetry_api_setting; end

      sig { abstract.returns(T.nilable(::Customer)) }
      def customer; end

      sig { abstract.params(actor: ::User).void }
      def disable_copilot!(actor); end

      sig { abstract.void }
      def telemetry_aggregation_disabled!; end

      sig { abstract.void }
      def telemetry_aggregation_enabled!; end

      sig { abstract.void }
      def telemetry_aggregation_no_policy!; end

      sig { abstract.params(actor: ::User).void }
      def enable_copilot_for_all_organizations!(actor); end

      sig { abstract.params(org_ids: T::Array[Integer], actor: ::User).void }
      def enable_copilot_for_selected_organizations!(org_ids, actor); end

      sig { abstract.returns(T::Boolean) }
      def has_copilot_organization?; end

      sig { abstract.returns(T::Boolean) }
      def has_trial_organization?; end

      sig { abstract.void }
      def no_chat_policy!; end

      sig { abstract.returns(T::Boolean) }
      def no_chat_policy?; end

      sig { abstract.void }
      def no_public_code_suggestions_policy!; end

      sig { abstract.returns(T::Boolean) }
      def no_public_code_suggestions_policy?; end

      sig { abstract.returns(T::Array[Copilot::BusinessTrial]) }
      def organization_trials; end

      sig { abstract.void }
      def private_telemetry_no_policy!; end

      sig { abstract.returns(T::Boolean) }
      def telemetry_aggregation_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def telemetry_aggregation_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def telemetry_aggregation_no_policy?; end

      sig { abstract.returns(T.nilable(String)) }
      def to_csv; end

      sig { abstract.returns(T::Boolean) }
      def user_feedback_opt_in_no_policy?; end
    end
  end
end
