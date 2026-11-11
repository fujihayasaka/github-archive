# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class SignupFlow < Base
    self.abstract_class = true

    connects_to database: { writing: :signup_flow_primary, reading: :signup_flow_readonly }

    def self.production_schema_name
      "signup_flow"
    end

    def self.throttler_cluster_name
      Ballast.throttler_cluster_name
    end
  end
end
