# frozen_string_literal: true

class CreateBlocklistMatches < ActiveRecord::Migration[5.2]
  def change
    create_table :blocklist_matches do |t|
      t.integer :blocklisted_term_id
      t.integer :advisory_review_id
      t.timestamps
      t.index [:blocklisted_term_id, :advisory_review_id], unique: true,
        name: "index_on_blocklisted_term_id_and_advisory_review_id"
      t.index :advisory_review_id
    end
  end
end
