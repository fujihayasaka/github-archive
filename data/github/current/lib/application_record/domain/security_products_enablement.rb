# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class SecurityProductsEnablement < ApplicationRecord::SecurityProductsEnablement
      self.abstract_class = true
    end
  end
end
