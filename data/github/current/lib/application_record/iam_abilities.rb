# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class IamAbilities < Base
    self.abstract_class = true

    connects_to database: { writing: :abilities_primary, reading: :abilities_readonly }
  end
end
