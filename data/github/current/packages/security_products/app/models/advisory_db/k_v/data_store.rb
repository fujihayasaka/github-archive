# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  class KV
    class DataStore < ApplicationRecord::Domain::RepositoriesNotify
      self.table_name = "advisory_database_key_values"
    end
  end
end
