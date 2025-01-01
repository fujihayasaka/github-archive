# typed: strict
# frozen_string_literal: true

module Marketplace
  class KV
    class DataStore < ApplicationRecord::Domain::Integrations
      self.table_name = "marketplace_key_values"
    end
  end
end
