# typed: strict
# frozen_string_literal: true

module Notices
  class Kv
    class DataStore < ApplicationRecord::Domain::FeatureManagement
      self.table_name = "notices_key_values"
    end
  end
end
