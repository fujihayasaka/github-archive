# frozen_string_literal: true

class AdvisoryPayloadBecomesLongBlob2 < ActiveRecord::Migration[6.0]
  def up
    change_column :advisory_reviews, :advisory_payload, "longblob", null: false
  end

  def down
    change_column :advisory_reviews, :advisory_payload, "text", null: false
  end
end
