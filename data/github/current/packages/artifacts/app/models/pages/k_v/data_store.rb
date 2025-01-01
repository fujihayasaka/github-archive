# typed: strict
# frozen_string_literal: true

module Pages
  class KV
    class DataStore < ApplicationRecord::Pages
      self.table_name = "pages_key_values"
    end
  end
end
