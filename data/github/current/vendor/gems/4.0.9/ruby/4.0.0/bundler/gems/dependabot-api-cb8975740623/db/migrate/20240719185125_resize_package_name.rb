# frozen_string_literal: true

class ResizePackageName < ActiveRecord::Migration[7.0]
  def change
    change_column :github_security_advisories, :dependency_name, :string, null: false, limit: 255 # rubocop:disable Rails/ReversibleMigration
  end
end
