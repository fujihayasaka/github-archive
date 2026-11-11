# typed: true
# frozen_string_literal: true

class CodeScanning::Settings::CodeqlStatusMenuComponent < ApplicationComponent
  attr_reader :repository
  attr_reader :codeql_last_scan_text
  attr_reader :latest_run_id
  attr_reader :codeql_workflow_path
  attr_reader :disabling_auto_codeql_restricted_by_security_configuration
  attr_reader :switching_to_adv_setup_restricted_by_security_configuration
  attr_reader :enabling_auto_codeql_restricted_by_security_configuration

  def initialize(
    repository:,
    codeql_last_scan_text: "View last scan log",
    auto_codeql_enabled: false,
    auto_codeql_updating: false,
    link_to_alerts: true,
    latest_run_id: nil,
    codeql_workflow_path: nil,
    disabling_auto_codeql_restricted_by_security_configuration: false,
    switching_to_adv_setup_restricted_by_security_configuration: false,
    enabling_auto_codeql_restricted_by_security_configuration: false,
    advanced_setup_enabled: false,
    code_quality_enabled: false
  )
    @repository = repository
    @auto_codeql_enabled = auto_codeql_enabled
    @auto_codeql_updating = auto_codeql_updating
    @codeql_last_scan_text = codeql_last_scan_text
    @link_to_alerts = link_to_alerts
    @latest_run_id = latest_run_id
    @codeql_workflow_path = codeql_workflow_path
    @disabling_auto_codeql_restricted_by_security_configuration = disabling_auto_codeql_restricted_by_security_configuration
    @switching_to_adv_setup_restricted_by_security_configuration = switching_to_adv_setup_restricted_by_security_configuration
    @enabling_auto_codeql_restricted_by_security_configuration = enabling_auto_codeql_restricted_by_security_configuration
    @advanced_setup_enabled = advanced_setup_enabled
    @code_quality_enabled = code_quality_enabled
  end

  def auto_codeql_enabled?
    @auto_codeql_enabled
  end

  def advanced_setup_enabled?
    @advanced_setup_enabled
  end

  def auto_codeql_updating?
    @auto_codeql_updating
  end

  def auto_codeql_disable_dialog_id
    "auto-codeql-disable-dialog"
  end

  def auto_codeql_switch_dialog_id
    "auto-codeql-switch-dialog"
  end

  def auto_codeql_show_dialog_id
    "auto-codeql-config-dialog"
  end

  def codeql_last_scan_url
    "/#{repository.name_with_display_owner}/actions/runs/#{latest_run_id}"
  end

  def show_last_scan?
    latest_run_id.present?
  end

  def link_to_alerts?
    @link_to_alerts
  end

  def code_quality_enabled?
    @code_quality_enabled
  end
end
