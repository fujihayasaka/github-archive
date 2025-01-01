# typed: strict
# frozen_string_literal: true

module Marketplace
  class Domain
    module Provider
      extend T::Sig
      extend T::Helpers

      include Kernel
      include GitHub::Memoizer
      include GH::Domain::CallerService
      include GH::Domain::Provider::Base

      sig { returns(Marketplace::Domain) }
      memoize def marketplace_domain
        Marketplace::Domain.new(caller_service)
      end
    end
  end
end
