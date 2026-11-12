# frozen_string_literal: true

class AddAffectedFunctionsV1ToVulnerabilities < ActiveRecord::Migration[7.0]
  def change
    add_column :vulnerabilities, :affected_functions_v1, :mediumblob
  end
end
