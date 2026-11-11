# frozen_string_literal: true

class RenameAffectedVersionsToAffectedFunctionsInVulnerabilies < ActiveRecord::Migration[6.1]
  def change
    rename_column :vulnerabilities, :affected_versions, :affected_functions
  end
end
