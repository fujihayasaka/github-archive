# typed: strict
# frozen_string_literal: true

module Connect
  class KV
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "connect_key_values"
    end
  end
end
