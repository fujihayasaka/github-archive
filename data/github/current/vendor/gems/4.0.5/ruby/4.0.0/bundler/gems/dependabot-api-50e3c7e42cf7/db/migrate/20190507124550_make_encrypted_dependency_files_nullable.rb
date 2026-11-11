# frozen_string_literal: true

class MakeEncryptedDependencyFilesNullable < ActiveRecord::Migration[6.0]
  def change
    change_column_null(
      :pending_pull_requests,
      :encrypted_dependency_files,
      true,
    )
    change_column_null(
      :pending_pull_request_updates,
      :encrypted_dependency_files,
      true,
    )
  end
end
