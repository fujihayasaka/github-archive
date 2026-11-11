# typed: strict
# frozen_string_literal: true

module Explore
  class Kv
    class DataStore < ApplicationRecord::Domain::Explore
      self.table_name = "explore_key_values"
    end
  end
end
