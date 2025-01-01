# typed: strict
# frozen_string_literal: true

module Stratocaster
  class Domain
    module Provider
      extend T::Sig

      include GitHub::Memoizer
      include GH::Domain::CallerService
      include GH::Domain::Provider::Base

      sig { returns(Stratocaster::Domain) }
      memoize def stratocaster_domain
        Stratocaster::Domain.new(caller_service)
      end
    end
  end
end
