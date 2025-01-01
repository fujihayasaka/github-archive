# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Gotauth
      # The address of the gotauth service.
      #
      # e.g. "https://gotauth-production.service.iad.github.net"
      sig { returns(String) }
      attr_accessor :gotauth_address
    end
  end

  extend Config::Gotauth
end
