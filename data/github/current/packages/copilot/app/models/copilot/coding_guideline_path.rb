# typed: strict
# frozen_string_literal: true

module Copilot
  class CodingGuidelinePath < ApplicationRecord::Copilot

    self.table_name = "copilot_coding_guideline_paths"
    self.strict_loading_by_default = true

    belongs_to :copilot_coding_guideline,
      class_name: "Copilot::CodingGuideline",
      foreign_key: :copilot_coding_guideline_id,
      strict_loading: false,
      inverse_of: :paths

    validates :path, presence: true, uniqueness: { scope: :copilot_coding_guideline_id }
  end
end
