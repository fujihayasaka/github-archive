# typed: strict
# frozen_string_literal: true

module CodeScanning
  class KV
    class DataStore < ApplicationRecord::Domain::RepositoriesNotify
      self.table_name = "code_scanning_key_values"
    end
  end
end
