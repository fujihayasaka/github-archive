# frozen_string_literal: true

class AddReviewedToAdvisory < ActiveRecord::Migration[6.1]
  def change
    add_column :advisories, :reviewed, :boolean, default: true # rubocop:disable Rails/ThreeStateBooleanColumn
  end
end
