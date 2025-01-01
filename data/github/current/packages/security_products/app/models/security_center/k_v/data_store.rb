# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class KV
    class DataStore < ApplicationRecord::Domain::SecurityOverviewAnalytics
      self.table_name = "security_center_key_values"
    end
  end
end
