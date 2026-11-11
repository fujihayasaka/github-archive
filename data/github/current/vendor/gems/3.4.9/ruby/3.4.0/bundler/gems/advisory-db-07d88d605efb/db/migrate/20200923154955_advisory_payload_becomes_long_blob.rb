# frozen_string_literal: true

class AdvisoryPayloadBecomesLongBlob < ActiveRecord::Migration[6.0]
  def up
    change_column :feed_entries, :advisory_payload, "longblob", null: false
  end

  def down
    change_column :feed_entries, :advisory_payload, "text", null: false
  end
end
