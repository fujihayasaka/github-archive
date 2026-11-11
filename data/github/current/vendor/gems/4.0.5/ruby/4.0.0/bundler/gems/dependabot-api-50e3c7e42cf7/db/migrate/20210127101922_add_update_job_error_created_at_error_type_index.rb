# frozen_string_literal: true

class AddUpdateJobErrorCreatedAtErrorTypeIndex < ActiveRecord::Migration[6.0]
  def change
    add_index :update_job_errors, %i(error_type created_at)
  end
end
