# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class FeatureManagement < ApplicationRecord::FeatureManagement
      self.abstract_class = true
    end
  end
end
