# typed: strict
# frozen_string_literal: true

module Profiles
  class Kv
    class DataStore < ApplicationRecord::Domain::Profiles
      self.table_name = "profiles_munger_key_values"
    end
  end
end
