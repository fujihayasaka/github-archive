# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# PLEASE KEEP THESE SIGNATURES ALPHABETIZED BECAUSE IT MAKES
# PATRICK CRY WHEN THEY AREN'T
# ALSO, WHY DOES ! COME BEFORE ?
module Copilot
  module Signatures
    module Shared
      extend T::Helpers

      abstract!

      sig { abstract.void }
      def allow_public_code_suggestions!; end

      sig { abstract.returns(T::Boolean) }
      def allow_public_code_suggestions?; end

      sig { abstract.returns(T::Boolean) }
      def beta_features_github_chat_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def beta_features_github_chat_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def bing_github_chat_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def bing_github_chat_enabled?; end

      sig { abstract.void }
      def block_public_code_suggestions!; end

      sig { abstract.returns(T::Boolean) }
      def block_public_code_suggestions?; end

      sig { abstract.returns(T::Boolean) }
      def can_emit_usage?; end

      sig { abstract.returns(T::Boolean) }
      def can_export_premium_usage?; end

      sig { abstract.returns(T::Boolean) }
      def chat_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def chat_enabled?; end

      sig { abstract.returns(String) }
      def chat_setting; end

      sig { abstract.returns(T::Boolean) }
      def cli_configured?; end

      sig { abstract.void }
      def cli_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def cli_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def cli_enabled?; end

      sig { abstract.void }
      def cli_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def cli_no_policy?; end

      sig { abstract.void }
      def cli_no_policy!; end

      sig { abstract.returns(String) }
      def cli_setting; end

      sig { abstract.returns(T::Boolean) }
      def cli_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def desktop_configured?; end

      sig { abstract.void }
      def desktop_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def desktop_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def desktop_enabled?; end

      sig { abstract.void }
      def desktop_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def desktop_no_policy?; end

      sig { abstract.void }
      def desktop_no_policy!; end

      sig { abstract.returns(String) }
      def desktop_setting; end

      sig { abstract.returns(T::Boolean) }
      def desktop_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def editor_preview_features_configured?; end

      sig { abstract.void }
      def editor_preview_features_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def editor_preview_features_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def editor_preview_features_enabled?; end

      sig { abstract.void }
      def editor_preview_features_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def editor_preview_features_no_policy?; end

      sig { abstract.void }
      def editor_preview_features_no_policy!; end

      sig { abstract.returns(String) }
      def editor_preview_features_setting; end

      sig { abstract.returns(T::Boolean) }
      def editor_preview_features_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def a_chat_configured?; end

      sig { abstract.void }
      def a_chat_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def a_chat_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def a_chat_enabled?; end

      sig { abstract.void }
      def a_chat_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def a_chat_no_policy?; end

      sig { abstract.void }
      def a_chat_no_policy!; end

      sig { abstract.returns(String) }
      def a_chat_setting; end

      sig { abstract.returns(T::Boolean) }
      def a_chat_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def a_f_configured?; end

      sig { abstract.void }
      def a_f_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def a_f_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def a_f_enabled?; end

      sig { abstract.void }
      def a_f_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def a_f_no_policy?; end

      sig { abstract.void }
      def a_f_no_policy!; end

      sig { abstract.returns(String) }
      def a_f_setting; end

      sig { abstract.returns(T::Boolean) }
      def a_f_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def g_chat_configured?; end

      sig { abstract.void }
      def g_chat_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def g_chat_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def g_chat_enabled?; end

      sig { abstract.void }
      def g_chat_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def g_chat_no_policy?; end

      sig { abstract.void }
      def g_chat_no_policy!; end

      sig { abstract.returns(String) }
      def g_chat_setting; end

      sig { abstract.returns(T::Boolean) }
      def g_chat_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def o1_configured?; end

      sig { abstract.void }
      def o1_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def o1_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def o1_enabled?; end

      sig { abstract.void }
      def o1_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def o1_no_policy?; end

      sig { abstract.void }
      def o1_no_policy!; end

      sig { abstract.returns(String) }
      def o1_setting; end

      sig { abstract.returns(T::Boolean) }
      def o1_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def o3_configured?; end

      sig { abstract.void }
      def o3_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def o3_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def o3_enabled?; end

      sig { abstract.void }
      def o3_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def o3_no_policy?; end

      sig { abstract.void }
      def o3_no_policy!; end

      sig { abstract.returns(String) }
      def o3_setting; end

      sig { abstract.returns(T::Boolean) }
      def o3_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def o_ff_configured?; end

      sig { abstract.void }
      def o_ff_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def o_ff_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def o_ff_enabled?; end

      sig { abstract.void }
      def o_ff_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def o_ff_no_policy?; end

      sig { abstract.void }
      def o_ff_no_policy!; end

      sig { abstract.returns(String) }
      def o_ff_setting; end

      sig { abstract.returns(T::Boolean) }
      def o_ff_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def o_f_configured?; end

      sig { abstract.void }
      def o_f_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def o_f_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def o_f_enabled?; end

      sig { abstract.void }
      def o_f_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def o_f_no_policy?; end

      sig { abstract.void }
      def o_f_no_policy!; end

      sig { abstract.returns(String) }
      def o_f_setting; end

      sig { abstract.returns(T::Boolean) }
      def o_f_unconfigured?; end

      sig { abstract.returns(T.nilable(String)) }
      def copilot_billing_type; end

      sig { abstract.returns(T::Boolean) }
      def copilot_communication_opt_out?; end

      sig { abstract.returns(T::Boolean) }
      def copilot_extensions_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def copilot_extensions_configured?; end

      sig { abstract.void }
      def copilot_extensions_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def copilot_extensions_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def copilot_extensions_enabled?; end

      sig { abstract.void }
      def copilot_extensions_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def copilot_extensions_no_policy?; end

      sig { abstract.returns(String) }
      def copilot_extensions_setting; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_dotcom_configured?; end

      sig { abstract.void }
      def copilot_for_dotcom_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_dotcom_disabled?; end

      sig { abstract.void }
      def copilot_for_dotcom_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_dotcom_enabled?; end

      sig { abstract.void }
      def copilot_for_dotcom_no_policy!; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_dotcom_no_policy?; end

      sig { abstract.returns(String) }
      def copilot_for_dotcom_setting; end

      sig { abstract.void }
      def copilot_for_dotcom_unconfigured!; end

      sig { abstract.returns(T::Boolean) }
      def copilot_for_dotcom_unconfigured?; end

      sig { abstract.returns(String) }
      def copilot_plan; end

      sig { abstract.returns(T::Boolean) }
      def custom_models_configured?; end

      sig { abstract.void }
      def custom_models_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def custom_models_disabled?; end

      sig { abstract.void }
      def custom_models_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def custom_models_enabled?; end

      sig { abstract.void }
      def custom_models_no_policy!; end

      sig { abstract.returns(T::Boolean) }
      def custom_models_no_policy?; end

      sig { abstract.returns(String) }
      def custom_models_setting; end

      sig { abstract.returns(T::Boolean) }
      def custom_models_unconfigured?; end

      sig { abstract.void }
      def disable_chat!; end

      sig { abstract.void }
      def disable_dotcom_chat!; end

      sig { abstract.void }
      def disable_mobile_chat!; end

      sig { abstract.returns(T::Boolean) }
      def dotcom_chat_configured?; end

      sig { abstract.returns(T::Boolean) }
      def dotcom_chat_disabled?; end

      sig { abstract.void }
      def dotcom_chat_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def dotcom_chat_enabled?; end

      sig { abstract.void }
      def dotcom_chat_no_policy!; end

      sig { abstract.returns(T::Boolean) }
      def dotcom_chat_no_policy?; end

      sig { abstract.returns(String) }
      def dotcom_chat_setting; end

      sig { abstract.returns(T::Boolean) }
      def dotcom_chat_unconfigured?; end

      sig { abstract.void }
      def enable_chat!; end

      sig { abstract.void }
      def enable_mobile_chat!; end

      sig { abstract.returns(T::Boolean) }
      def mobile_chat_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def mobile_chat_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def mobile_chat_no_policy?; end

      sig { abstract.returns(T::Boolean) }
      def pr_summarizations_configured?; end

      sig { abstract.void }
      def pr_summarizations_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def pr_summarizations_disabled?; end

      sig { abstract.void }
      def pr_summarizations_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def pr_summarizations_enabled?; end

      sig { abstract.void }
      def pr_summarizations_no_policy!; end

      sig { abstract.returns(T::Boolean) }
      def pr_summarizations_no_policy?; end

      sig { abstract.returns(String) }
      def pr_summarizations_setting; end

      sig { abstract.returns(T::Boolean) }
      def pr_summarizations_unconfigured?; end

      sig { abstract.returns(T.nilable(String)) }
      def premium_usage_csv; end

      sig { abstract.returns(T::Boolean) }
      def private_docs_configured?; end

      sig { abstract.void }
      def private_docs_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def private_docs_disabled?; end

      sig { abstract.void }
      def private_docs_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def private_docs_enabled?; end

      sig { abstract.void }
      def private_docs_no_policy!; end

      sig { abstract.returns(T::Boolean) }
      def private_docs_no_policy?; end

      sig { abstract.returns(String) }
      def private_docs_setting; end

      sig { abstract.returns(T::Boolean) }
      def private_docs_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def private_telemetry_unconfigured?; end

      sig { abstract.returns(T::Boolean) }
      def private_telemetry_configured?; end

      sig { abstract.void }
      def private_telemetry_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def private_telemetry_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def private_telemetry_enabled?; end

      sig { abstract.void }
      def private_telemetry_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def private_telemetry_no_policy?; end

      sig { abstract.returns(String) }
      def private_telemetry_setting; end

      sig { abstract.returns(T::Boolean) }
      def public_code_suggestions_configured?; end

      sig { abstract.returns(String) }
      def snippy_setting; end

      sig { abstract.returns(T::Boolean) }
      def user_feedback_opt_in_enabled?; end

      sig { abstract.returns(T::Boolean) }
      def user_feedback_opt_in_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def overages_configured?; end

      sig { abstract.void }
      def overages_disabled!; end

      sig { abstract.returns(T::Boolean) }
      def overages_disabled?; end

      sig { abstract.returns(T::Boolean) }
      def overages_enabled?; end

      sig { abstract.void }
      def overages_enabled!; end

      sig { abstract.returns(T::Boolean) }
      def overages_no_policy?; end

      sig { abstract.void }
      def overages_no_policy!; end

      sig { abstract.returns(String) }
      def overages_setting; end

      sig { abstract.returns(T::Boolean) }
      def overages_unconfigured?; end
    end

    extend T::Helpers

    abstract!

    sig { abstract.params(msg: String, room_id: T.nilable(String)).void }
    def chatterbox_say(msg, room_id: nil); end

    sig do
      abstract.type_parameters(:A).params(
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def with_read(&block); end

    sig do
      abstract.type_parameters(:A).params(
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def with_write(&block); end
  end
end
