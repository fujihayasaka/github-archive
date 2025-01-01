# typed: true
# frozen_string_literal: true

class CodeScanning::Settings::AutoCodeqlSetupMenuComponent < ApplicationComponent
  include CodeScanningHelper

  attr_reader :repository
  attr_reader :enabling_auto_codeql_restricted_by_security_configuration

  def initialize(repository:, runners_error:, enabling_auto_codeql_restricted_by_security_configuration: false)
    @repository = repository
    @runners_error = runners_error
    @enabling_auto_codeql_restricted_by_security_configuration = enabling_auto_codeql_restricted_by_security_configuration
  end

  def runners_error?
    @runners_error.present?
  end

  def runners_error_message
    case @runners_error
    when :no_runners_assigned
      "No GitHub Actions runners with label code-scanning are assigned to this repository. Assign some runners with that label or use the advanced setup instead."
    when :no_macos_runners_assigned
      "No GitHub Actions runners with label code-scanning and macOS are assigned to this repository. Assign some runners with those labels or use the advanced setup instead."
    end
  end

  def auto_codeql_show_dialog_id
    "auto-codeql-config-dialog"
  end

  def auto_codeql_button_test_selector
    if enabling_auto_codeql_restricted_by_security_configuration
      "blocked-by-enforced-config"
    elsif runners_error?
      "runners-error"
    else
      "supported-languages"
    end
  end

  def auto_codeql_button_text
    if enabling_auto_codeql_restricted_by_security_configuration
      "Blocked by organization"
    elsif runners_error?
      runners_error_message
    else
      "CodeQL will automatically find the best configuration for your repository."
    end
  end

  def item_custom_css
    "max-width: 290px"
  end

  def auto_codeql_button_disabled?
    enabling_auto_codeql_restricted_by_security_configuration || runners_error?
  end
end
