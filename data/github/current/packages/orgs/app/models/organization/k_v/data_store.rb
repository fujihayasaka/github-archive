# typed: strict
# frozen_string_literal: true

class Organization
  class KV
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "organizations_key_values"
    end
  end
end
