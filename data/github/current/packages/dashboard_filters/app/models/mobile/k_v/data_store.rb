# typed: strict
# frozen_string_literal: true

module Mobile
  class KV
    class DataStore < ApplicationRecord::Domain::UsersCollab
      self.table_name = "mobile_key_values"
    end
  end
end
