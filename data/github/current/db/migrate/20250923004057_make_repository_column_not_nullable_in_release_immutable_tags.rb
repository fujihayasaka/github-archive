# typed: true
# frozen_string_literal: true

class MakeRepositoryColumnNotNullableInReleaseImmutableTags < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_column_null :release_immutable_tags, :repository_name, false
  end
end
