# frozen_string_literal: true

class AddCVSSV3ToAdvisories < ActiveRecord::Migration[6.0]
  def change
    add_column :advisories, :cvss_v3, :binary, limit: 255, null: true
    add_column :advisory_reviews, :cvss_v3, :binary, limit: 255, null: true
    add_column :cve_requests, :cvss_v3, :binary, limit: 255, null: true
    add_column :feed_entries, :cvss_v3, :binary, limit: 255, null: true
  end
end
