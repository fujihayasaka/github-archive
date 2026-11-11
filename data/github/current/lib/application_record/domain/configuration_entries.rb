# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class ConfigurationEntries < ApplicationRecord::Configurations
      self.abstract_class = true
    end
  end
end
