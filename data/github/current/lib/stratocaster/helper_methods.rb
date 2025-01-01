# typed: false
# frozen_string_literal: true

module Stratocaster
  module HelperMethods
    def self.included(model)
      model.before_validation :set_timestamps, on: :create
    end

    private

    def set_timestamps
      self.created_at = self.updated_at = Time.now.utc
    end
  end
end
