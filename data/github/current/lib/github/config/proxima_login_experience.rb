# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ProximaLoginExperience
      def proxima_login_experience?
        GitHub.multi_tenant_enterprise?
      end
    end
  end

  extend Config::ProximaLoginExperience
end
