# frozen_string_literal: true

class AddMetricMetadataToUpdateJobs < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :metrics_metadata, :json
  end
end
