# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class Domain < GH::Domain::Base
    include GitHub::Memoizer

    # Returns a domain dealing with security configurations.
    sig { returns(SecurityProductsEnablement::Domain::Configurations) }
    memoize def configurations
      SecurityProductsEnablement::Domain::Configurations.new
    end
  end
end
