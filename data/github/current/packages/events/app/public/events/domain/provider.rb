# typed: strict
# frozen_string_literal: true

module Events
  class Domain
    module Provider
      extend T::Helpers

      requires_ancestor { Kernel }

      include GitHub::Memoizer
      include GH::Domain::CallerService
      include GH::Domain::Provider::Base

      sig { returns(Events::Domain) }
      memoize def events_domain
        Events::Domain.new(caller_service)
      end
    end
  end
end
