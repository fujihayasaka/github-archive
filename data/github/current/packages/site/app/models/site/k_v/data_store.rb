# typed: strict
# frozen_string_literal: true

module Site
  class KV
    class DataStore < ApplicationRecord::Domain::Site
      self.table_name = "marketing_platform_key_values"
    end
  end
end
