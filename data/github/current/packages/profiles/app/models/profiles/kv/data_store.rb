# typed: strict
# frozen_string_literal: true

module Profiles
  class Kv
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "profiles_key_values"
    end
  end
end
