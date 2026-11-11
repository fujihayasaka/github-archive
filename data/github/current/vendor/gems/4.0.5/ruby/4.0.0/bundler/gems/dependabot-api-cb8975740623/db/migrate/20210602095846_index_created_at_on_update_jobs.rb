# frozen_string_literal: true

class IndexCreatedAtOnUpdateJobs < ActiveRecord::Migration[6.0]
  def change
    add_index :update_jobs, :created_at
  end
end
