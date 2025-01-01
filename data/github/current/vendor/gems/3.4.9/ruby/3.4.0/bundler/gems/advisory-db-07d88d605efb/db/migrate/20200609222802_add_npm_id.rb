# frozen_string_literal: true

class AddNPMID < ActiveRecord::Migration[6.0]
  def change
    # Add NPM ID to all advisory related tables, so that it can be sent into dotcom.
    # tables needing NPM ID are feed_entries, advisory_reviews, advisories
    # this should work similar to the existing cve_id and whitesource_id columns
    #
    # Note that npm_id is not required to be unique on feed entries,
    # but is required to be unique on advisories and advisory_reviews (just like cve_id/whitesource_id).
    # This is because feed_entries from differing sources could reference the same npm id,
    # and thus should rollup to the same advisory-review/advisory.

    add_column :feed_entries, :npm_id, :integer, unsigned: true, null: true, default: nil
    add_index :feed_entries, :npm_id, unique: false

    add_column :advisory_reviews, :npm_id, :integer, unsigned: true, null: true, default: nil
    add_index :advisory_reviews, :npm_id, unique: true

    add_column :advisories, :npm_id, :integer, unsigned: true, null: true, default: nil
    add_index :advisories, :npm_id, unique: true
  end
end
