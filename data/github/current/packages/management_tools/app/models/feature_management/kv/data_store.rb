# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class Kv
    class DataStore < ApplicationRecord::Collab
      self.table_name = "feature_management_key_values"
    end
  end
end
