# frozen_string_literal: true

class AddNVDPublishedAtToAdvisories < ActiveRecord::Migration[7.0]
  def change
    add_column :advisories, :nvd_published_at, :datetime, precision: 6, null: true
  end
end
