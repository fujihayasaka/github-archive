# typed: true
# frozen_string_literal: true

class DropArchivedRepositorySequences < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    drop_table :archived_repository_sequences, if_exists: true
  end
end
