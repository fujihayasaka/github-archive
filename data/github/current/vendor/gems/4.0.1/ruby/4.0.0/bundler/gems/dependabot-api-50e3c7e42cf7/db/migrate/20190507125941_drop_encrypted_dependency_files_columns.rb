# frozen_string_literal: true

class DropEncryptedDependencyFilesColumns < ActiveRecord::Migration[6.0]
  def change
    remove_column(
      :pending_pull_requests,
      :encrypted_dependency_files,
      :text,
    )
    remove_column(
      :pending_pull_request_updates,
      :encrypted_dependency_files,
      :text,
    )
  end
end
