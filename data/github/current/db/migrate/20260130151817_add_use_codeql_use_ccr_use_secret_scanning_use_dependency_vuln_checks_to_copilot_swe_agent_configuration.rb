# typed: true
# frozen_string_literal: true

class AddUseCodeqlUseCcrUseSecretScanningUseDependencyVulnChecksToCopilotSweAgentConfiguration < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_swe_agent_configuration, bulk: true do |t|
      t.column :use_codeql, :boolean, null: false, default: true, comment: "Whether copilot_swe_agent uses code scanning with CodeQL to review its work"
      t.column :use_ccr, :boolean, null: false, default: true, comment: "Whether copilot_swe_agent uses Copilot Code Review to check its work"
      t.column :use_secret_scanning, :boolean, null: false, default: true, comment: "Whether copilot_swe_agent uses secret scanning to check its work"
      t.column :use_dependency_vuln_checks, :boolean, null: false, default: true, comment: "Whether copilot_swe_agent uses dependency vulnerability checks against the GitHub Advisory Database to check its work"
    end
  end
end
