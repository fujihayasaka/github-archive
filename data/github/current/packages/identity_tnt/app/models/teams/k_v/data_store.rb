# typed: strict
# frozen_string_literal: true

module Teams
  class KV
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "identity_tnt_key_values"
    end
  end
end
