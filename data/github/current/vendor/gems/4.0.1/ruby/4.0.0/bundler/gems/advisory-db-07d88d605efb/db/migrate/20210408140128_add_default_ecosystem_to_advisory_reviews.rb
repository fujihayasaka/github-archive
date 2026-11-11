# frozen_string_literal: true

class AddDefaultEcosystemToAdvisoryReviews < ActiveRecord::Migration[6.0]
  def up
    add_column :advisory_reviews, :default_ecosystem, :string, limit: 40
    add_index :advisory_reviews, [:state, :default_ecosystem]
    remove_index :advisory_reviews, :state
  end

  def down
    add_index :advisory_reviews, :state
    remove_index :advisory_reviews, [:state, :default_ecosystem]
    remove_column :advisory_reviews, :default_ecosystem
  end
end
