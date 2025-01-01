# frozen_string_literal: true

class RemoveDeprecatedColumns < ActiveRecord::Migration[6.1]
  def change
    remove_index :advisory_reviews, :pull_request_number
    remove_column :advisory_reviews, :pull_request_number, :integer
    remove_column :advisory_reviews, :reviewer_modified, :boolean
    remove_column :advisory_reviews, :curate_on_inbox, :boolean

    remove_index :cve_reviews, :pull_request_number
    remove_column :cve_reviews, :pull_request_number, :integer
    remove_column :cve_reviews, :curate_on_inbox, :boolean
  end
end
