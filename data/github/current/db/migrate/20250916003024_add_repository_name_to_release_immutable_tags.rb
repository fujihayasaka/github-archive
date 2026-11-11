# typed: true
# frozen_string_literal: true

class AddRepositoryNameToReleaseImmutableTags < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table(:release_immutable_tags, bulk: true) do |t|
      t.column :repository_name, :string, limit: 255, null: true, after: :repository_id
    end
  end
end
