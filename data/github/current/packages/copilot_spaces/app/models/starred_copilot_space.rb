# typed: true
# frozen_string_literal: true

class StarredCopilotSpace < ApplicationRecord::Copilot
  self.table_name = "starred_custom_copilots"
  belongs_to :user, inverse_of: :starred_copilot_spaces
  belongs_to :copilot_space, foreign_key: "custom_copilot_id", inverse_of: :stars

  delegate :name, to: :copilot_space
end
