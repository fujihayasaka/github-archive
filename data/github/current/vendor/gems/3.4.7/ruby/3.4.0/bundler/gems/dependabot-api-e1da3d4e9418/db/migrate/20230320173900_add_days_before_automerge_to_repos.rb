# frozen_string_literal: true

class AddDaysBeforeAutomergeToRepos < ActiveRecord::Migration[7.0]
  def change
    add_column :repos, :days_before_automerge, :integer
  end
end
