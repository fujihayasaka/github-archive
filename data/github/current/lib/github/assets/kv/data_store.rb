# typed: strict
# frozen_string_literal: true

module Assets
  class KV
    class DataStore < ApplicationRecord::Domain::AssetKeyValues
      self.table_name = "asset_key_values"
    end
  end
end
