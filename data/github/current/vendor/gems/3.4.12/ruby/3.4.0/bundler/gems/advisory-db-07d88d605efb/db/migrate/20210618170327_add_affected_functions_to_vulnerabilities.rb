# frozen_string_literal: true

class AddAffectedFunctionsToVulnerabilities < ActiveRecord::Migration[6.1]
  def change
    add_column :vulnerabilities, :affected_versions, :mediumblob, null: true, default: nil
  end
end
