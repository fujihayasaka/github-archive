# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Configsd
      # The url of the configsd service.
      #
      # e.g. "https://configsd-production.service.iad.github.net"
      sig { returns(T.nilable(String)) }
      attr_accessor :configsd_url

      sig { returns(String) }
      attr_accessor :configsd_mesh_url

      sig { returns(String) }
      attr_accessor :configsd_hmac_key
    end
  end

  extend Config::Configsd
end
