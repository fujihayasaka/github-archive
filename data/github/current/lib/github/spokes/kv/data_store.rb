# typed: strict
# frozen_string_literal: true

module Spokes
  class KV
    class DataStore < ApplicationRecord::Domain::Spokes
      self.table_name = "spokes_key_values"
    end
  end
end
