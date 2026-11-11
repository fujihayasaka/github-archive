# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Spokes < ApplicationRecord::Spokes
      self.abstract_class = true

      def self.transaction
        super(requires_new: true)
      end
    end
  end
end
