# typed: true
# frozen_string_literal: true

class CreateCopilotInsightsActivities < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_insights_activities, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.blob :engagement_events
      t.blob :loc_suggested
      t.blob :loc_accepted
      t.blob :code_suggestion_events
      t.blob :code_suggestion_events_accepted
      t.blob :prs_merged
      t.blob :pr_lead_time
      t.blob :commit_count

      t.datetime :engagement_events_updated_at, precision: 6
      t.datetime :loc_suggested_updated_at, precision: 6
      t.datetime :loc_accepted_updated_at, precision: 6
      t.datetime :code_suggestion_events_updated_at, precision: 6
      t.datetime :code_suggestion_events_accepted_updated_at, precision: 6
      t.datetime :prs_merged_updated_at, precision: 6
      t.datetime :pr_lead_time_updated_at, precision: 6
      t.datetime :commit_count_updated_at, precision: 6
    end
  end
end
