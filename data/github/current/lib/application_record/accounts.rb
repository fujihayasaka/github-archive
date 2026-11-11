# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Accounts < Base
    self.abstract_class = true

    connects_to database: { writing: :accounts_primary, reading: :accounts_readonly }

    def self.production_schema_name
      "accounts"
    end

    def self.throttler_cluster_name
      Ballast.throttler_cluster_name
    end
  end
end
