# typed: true
# frozen_string_literal: true

module GitHub
  module TokenScanning
    module Service
      autoload :Client, "github/token_scanning/service/client"
      autoload :RelatedPublicLeak, "github/token_scanning/service/related_public_leak"
      autoload :RelatedToken, "github/token_scanning/service/related_token"
      autoload :Token, "github/token_scanning/service/token"
      autoload :TokenLocation, "github/token_scanning/service/token_location"
    end
  end
end
