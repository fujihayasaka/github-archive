# frozen_string_literal: true

class AddCurateOnInboxColumns < ActiveRecord::Migration[6.0]
  def change
    add_column :advisory_reviews, :curate_on_inbox, :boolean, default: false, null: false
    add_column :cve_reviews, :curate_on_inbox, :boolean, default: false, null: false
  end
end
