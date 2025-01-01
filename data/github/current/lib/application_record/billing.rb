# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Billing < Base
    self.abstract_class = true

    connects_to database: { writing: :billing_primary, reading: :billing_readonly }
  end
end
