# typed: true
# frozen_string_literal: true

# GitHub/DoNotAddUniqueIndexToExistingColumn is deliberately disabled,
# because we have done the work to ensure there are no duplicates that
# would cause a problem with adding this index.

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class AddIndexForRepositoryNameInReleaseImmutableTags < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :release_immutable_tags, bulk: true do |t|
      t.index [:repository_name, :tag_name], unique: true, name: "index_release_immutable_tags_on_repository_name_and_tag_name"
    end
  end
end
