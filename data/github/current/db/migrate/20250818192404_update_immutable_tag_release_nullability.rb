# typed: true
# frozen_string_literal: true

class UpdateImmutableTagReleaseNullability < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_column_null :release_immutable_tags, :release_id, true
  end
end
