# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class KV
    class DataStore < ApplicationRecord::Domain::Copilot
      self.table_name = "runtime_key_values"
    end
  end
end
