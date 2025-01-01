# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Copilot < Base
    self.abstract_class = true

    connects_to database: { writing: :copilot_primary, reading: :copilot_readonly }
  end
end
