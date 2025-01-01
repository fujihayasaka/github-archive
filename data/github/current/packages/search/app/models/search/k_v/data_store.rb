# typed: strict
# frozen_string_literal: true

module Search
  class KV
    class DataStore < ApplicationRecord::Domain::Search
      self.table_name = "elastic_search_key_values"
    end
  end
end
