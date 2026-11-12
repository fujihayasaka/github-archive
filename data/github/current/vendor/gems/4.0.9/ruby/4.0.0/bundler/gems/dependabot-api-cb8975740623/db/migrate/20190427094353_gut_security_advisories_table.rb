# frozen_string_literal: true

class GutSecurityAdvisoriesTable < ActiveRecord::Migration[6.0]
  def change
    remove_column :security_advisories, :source_url, :string
    remove_column :security_advisories, :url, :string
    remove_column :security_advisories, :title, :string
    remove_column :security_advisories, :description, :text
    remove_column :security_advisories, :cve, :string, limit: 150
    remove_column :security_advisories, :date, :date
  end
end
