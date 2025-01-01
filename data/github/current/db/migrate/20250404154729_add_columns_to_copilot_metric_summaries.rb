# typed: true
# frozen_string_literal: true

class AddColumnsToCopilotMetricSummaries < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_metric_summaries, bulk: true do |t|
      t.json :code_suggestion_events, after: :dormant_seats
      t.json :loc_generated, after: :code_suggestion_events
      t.json :commit_counts, after: :loc_generated
      t.json :prs_merged, after: :commit_counts
      t.json :pr_lead_times, after: :prs_merged
    end
  end
end
