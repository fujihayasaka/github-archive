# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module ApplicationRecord
  class Lodge < Base
    self.abstract_class = true

    connects_to database: { writing: :lodge_primary, reading: :lodge_readonly }
  end
end
