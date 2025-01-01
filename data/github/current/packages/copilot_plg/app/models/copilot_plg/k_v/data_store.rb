# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class KV
    class DataStore < ApplicationRecord::Domain::CopilotPLG
      self.table_name = "copilot_plg_key_values"
    end
  end
end
