# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Billing < ApplicationRecord::Billing
      self.abstract_class = true
    end
  end
end
