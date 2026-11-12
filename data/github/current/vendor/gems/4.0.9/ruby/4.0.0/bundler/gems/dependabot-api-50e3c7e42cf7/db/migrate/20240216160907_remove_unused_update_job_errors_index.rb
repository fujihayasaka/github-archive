# frozen_string_literal: true

class RemoveUnusedUpdateJobErrorsIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index(
      :update_job_errors,
      %w(error_type created_at),
      name: "index_update_job_errors_on_error_type_and_created_at"
    )
  end
end
