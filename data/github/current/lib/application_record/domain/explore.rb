# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Explore < ApplicationRecord::Ballast
      self.abstract_class = true
    end
  end
end
