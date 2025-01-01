# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Stratocaster < ApplicationRecord::Stratocaster
      self.abstract_class = true
    end
  end
end
