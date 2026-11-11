# typed: strict
# frozen_string_literal: true

module Apps
  class KV
    class DataStore < ApplicationRecord::Domain::IntegrationsLodge
      self.table_name = "apps_key_values"
    end
  end
end
