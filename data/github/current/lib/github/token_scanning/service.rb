# typed: true
# frozen_string_literal: true

module GitHub
  module TokenScanning
    module Service
      autoload :Client, "github/token_scanning/service/client"
      autoload :Token, "github/token_scanning/service/token"
      autoload :TokenLocation, "github/token_scanning/service/token_location"
    end
  end
end
