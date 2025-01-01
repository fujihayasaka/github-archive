# typed: strict
# frozen_string_literal: true

module Copilot
  class KV
    class DataStore < ApplicationRecord::Domain::Copilot
      self.table_name = "copilot_key_values"
    end
  end
end
