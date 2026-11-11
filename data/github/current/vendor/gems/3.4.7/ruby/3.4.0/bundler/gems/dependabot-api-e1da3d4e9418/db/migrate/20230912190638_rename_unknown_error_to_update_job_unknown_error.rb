# frozen_string_literal: true

class RenameUnknownErrorToUpdateJobUnknownError < ActiveRecord::Migration[7.0]
  def change
    rename_table :unknown_errors, :update_job_unknown_errors
  end
end
