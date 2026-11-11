# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class TokenScanningService < ApplicationRecord::TokenScanningService
      self.abstract_class = true
    end
  end
end
