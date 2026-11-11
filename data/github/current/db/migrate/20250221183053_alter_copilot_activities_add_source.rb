# typed: true
# frozen_string_literal: true

class AlterCopilotActivitiesAddSource < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_activities, bulk: true do |t|
      t.string :activity_source
    end
  end
end
