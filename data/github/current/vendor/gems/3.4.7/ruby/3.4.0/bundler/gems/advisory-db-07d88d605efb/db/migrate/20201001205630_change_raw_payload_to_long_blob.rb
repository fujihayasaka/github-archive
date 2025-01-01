# frozen_string_literal: true

class ChangeRawPayloadToLongBlob < ActiveRecord::Migration[6.0]
  def up
    change_column :feed_entries, :raw_payload, "longblob"
  end

  def down
    change_column :feed_entries, :raw_payload, "longtext"
  end
end
