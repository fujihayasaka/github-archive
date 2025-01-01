# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class CopilotPLG < ApplicationRecord::Copilot
      self.abstract_class = true
    end
  end
end
