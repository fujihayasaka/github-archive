# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Reposd
      # The url of the reposd service.
      #
      # e.g. "https://reposd-production.service.iad.github.net"
      sig { returns(String) }
      attr_accessor :reposd_url

      # The url of the reposd twirp service.
      #
      # e.g. "http://reposd-twirp-api.reposd-production.svc.cluster.local"
      sig { returns(T.nilable(String)) }
      attr_accessor :reposd_twirp_url

      sig { returns(String) }
      attr_accessor :reposd_hmac_key
    end
  end

  extend Config::Reposd
end
