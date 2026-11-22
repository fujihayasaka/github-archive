# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Freno
      def freno_enabled?
        return false unless GitHub::AppEnvironment.production?
        return false if GitHub.staging_lab?
        return false if GitHub.environment.fetch("FRENO_DISABLED", "0") == "1"
        return GitHub.environment.fetch("ENTERPRISE_MYSQL_FRENO_ENABLED", "0") == "1" if GitHub.enterprise?
        true
      end
    end
  end

  extend Config::Freno
end
