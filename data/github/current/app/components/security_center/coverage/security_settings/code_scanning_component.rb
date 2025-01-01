# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module SecuritySettings
      class CodeScanningComponent < ApplicationComponent
        extend T::Sig
        include CodeScanningHelper

        TEST_SELECTOR = "security-center-coverage-security-settings-code-scanning"
        SUITE_SELECTOR_TEST_SELECTOR = "security-center-coverage-security-settings-code-scanning-suite-selector"

        sig { params(enablement_data: Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data).void }
        def initialize(enablement_data)
          @enablement_data = enablement_data
        end

        sig { returns(T::Boolean) }
        def render?
          feature_available?
        end

        sig { returns(T::Boolean) }
        def setting_disabled?
          @enablement_data.code_scanning_default_setup_blocked_by_in_progress_setting ||
            @enablement_data.code_scanning_default_setup_onboarding_status == "enabling" ||  # We don't want users disabling when it's in an "enabling" state
            @enablement_data.code_scanning_default_setup_prerequisite_error_message.present? ||
            !default_setup_eligible?
        end

        sig { returns(T::Boolean) }
        def feature_available?
          return false unless @enablement_data.show_unarchived_features

          @enablement_data.code_scanning_default_setup_visible ||
            @enablement_data.code_scanning_default_setup_public_scanning_visible
        end

        sig { returns(T::Boolean) }
        def feature_enabled?
          @enablement_data.code_scanning_default_setup_user_has_enabled
        end

        sig { returns(T::Boolean) }
        def default_setup_eligible?
          @enablement_data.code_scanning_default_setup_eligible && @enablement_data.code_scanning_default_setup_onboarding_status != "setup_failed"
        end

        sig { returns(T::Boolean) }
        memoize def manual_setup_enabled?
          CodeScanning::AutoCodeql.new(current_repository).has_manual_workflow?
        end

        sig { returns(String) }
        def feature_description
          if @enablement_data.code_scanning_default_setup_blocked_by_in_progress_setting
            "Setup in progress. Please try again later."
          elsif @enablement_data.code_scanning_default_setup_onboarding_status == "setup_failed"
            safe_join(["There was an error enabling CodeQL. ", default_error_message])
          elsif @enablement_data.code_scanning_default_setup_onboarding_status == "enabling"
            "Setup in progress."
          elsif @enablement_data.code_scanning_default_setup_onboarding_status == "updating"
            "Updating configuration."
          elsif @enablement_data.code_scanning_default_setup_prerequisite_error_message.present?
            @enablement_data.code_scanning_default_setup_prerequisite_error_message
          elsif default_setup_eligible?
            safe_join([
              "Identify vulnerabilities and errors with ",
              ActionController::Base.helpers.link_to("CodeQL", codeql_docs_href),
              " for ",
              ActionController::Base.helpers.link_to("eligible", eligible_repositories_docs_href),
              " repositories. This will automatically find the best configuration for your selected repository based on the chosen ",
              ActionController::Base.helpers.link_to("query suite", built_in_codeql_query_suites_docs_path(current_organization)),
              "."
            ])
          else
            safe_join(["This repository is not eligible for CodeQL default setup. ", docs_message])
          end
        end

        private

        sig { returns(String) }
        def default_error_message
          safe_join([
            "Please see this repository's ",
            ActionController::Base.helpers.link_to(
              "settings page",
              repo_settings_path
            ),
            " for more information."
          ])
        end

        sig { returns(String) }
        def docs_message
          link_to "What makes a repository eligible for default setup?", eligible_repositories_docs_href
        end

        sig { returns(Integer) }
        def left_margin
          @enablement_data.code_scanning_default_setup_public_scanning_visible ? 0 : 3
        end

        sig { returns(Integer) }
        def heading_font_size
          @enablement_data.advanced_security_visible ? 4 : 3
        end

        sig { returns(String) }
        def repo_settings_path
          repository_security_and_analysis_path(current_organization, current_repository, anchor: "code_scanning_settings")
        end

        sig { returns(String) }
        def codeql_docs_href
          "#{GitHub.help_url(ghec_exclusive: true)}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning-with-codeql"
        end

        sig { returns(String) }
        def eligible_repositories_docs_href
          "#{GitHub.help_url(ghec_exclusive: true)}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/configuring-code-scanning-at-scale#eligible-repositories-for-codeql-default-setup"
        end

        sig { returns(T::Array[{ label: String, value: String, description: String }]) }
        def suite_options
          CodeScanning::AutoCodeql.query_suite_options(current_organization)
        end

        sig { returns(T::Boolean) }
        def render_suite_selector?
          !setting_disabled? && @enablement_data.code_scanning_default_setup_onboarding_status != "updating"
        end

        sig { returns(T.nilable(String)) }
        def active_suite
          @enablement_data.code_scanning_default_setup_active_suite
        end

        sig { returns(String) }
        def recommended_suite
          @enablement_data.code_scanning_default_setup_recommended_suite
        end

        sig { returns(String) }
        def initial_suite_selection
          active_suite || recommended_suite
        end
      end
    end
  end
end
