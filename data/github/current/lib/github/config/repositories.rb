# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Repositories
      def public_repositories_available?
        !GitHub.multi_tenant_enterprise?
      end
    end
  end

  extend Config::Repositories
end
