# typed: strict
# frozen_string_literal: true

module Repositories
  class Kv
    class DataStore < ApplicationRecord::Repositories
      self.table_name = "repositories_key_values"
    end
  end
end
