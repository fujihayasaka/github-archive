# frozen_string_literal: true

class AddPublishedAtToAdvisories < ActiveRecord::Migration[6.1]
  def change
    add_column :advisories, :published_at, :datetime
  end
end
