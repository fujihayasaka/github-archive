# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module GitHubFeCore
      # The url of the github-fe-core service.
      #
      # e.g. "https://github-fe-core-production.service.iad.github.net/"
      sig { returns(String) }
      attr_accessor :github_fe_core_url

      sig { returns(String) }
      attr_accessor :github_fe_core_hmac_key
    end
  end

  extend Config::GitHubFeCore
end
