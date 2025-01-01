# typed: ignore
# frozen_string_literal: true

module ApplicationRecord
  class Configurations < Base
    self.abstract_class = true

    connects_to database: { writing: :configurations_primary, reading: :configurations_readonly }
  end
end
