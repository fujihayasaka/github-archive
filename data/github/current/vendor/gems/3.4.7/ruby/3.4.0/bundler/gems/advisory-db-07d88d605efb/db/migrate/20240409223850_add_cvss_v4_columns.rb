# frozen_string_literal: true

class AddCVSSV4Columns < ActiveRecord::Migration[7.1]
  def change
    add_column :advisory_payloads, :cvss_v4, :string, limit: 255, null: true
    add_column :cve_reviews, :cvss_v4, :string, limit: 255, null: true
    add_column :cve_requests, :cvss_v4, :string, limit: 255, null: true
    add_column :advisories, :cvss_v4, :string, limit: 255, null: true
  end
end
