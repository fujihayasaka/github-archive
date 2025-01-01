# typed: strict
# frozen_string_literal: true

module Stars
  class Kv
    class DataStore < ApplicationRecord::Mysql1
      self.table_name = "stars_key_values"
    end
  end
end
