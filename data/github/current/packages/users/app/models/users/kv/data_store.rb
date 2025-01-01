# typed: strict
# frozen_string_literal: true

module Users
  class Kv
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "users_key_values"
    end
  end
end
