# typed: strict
# frozen_string_literal: true

module Sponsors
  class KV
    class DataStore < ApplicationRecord::Domain::Sponsors
      self.table_name = "sponsors_key_values"
    end
  end
end
