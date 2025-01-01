# frozen_string_literal: true

class RenamePayloads < ActiveRecord::Migration[5.2]
  def change
    rename_column :advisory_reviews, :payload, :advisory_payload
    rename_column :feed_entries, :payload, :raw_payload
    rename_column :feed_entries, :review_payload, :advisory_payload
  end
end
