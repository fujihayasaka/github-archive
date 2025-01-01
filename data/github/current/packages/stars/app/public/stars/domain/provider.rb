# typed: strict
# frozen_string_literal: true

module Stars
  class Domain
    module Provider
      extend T::Sig
      extend T::Helpers

      requires_ancestor { Kernel }

      include GitHub::Memoizer
      include GH::Domain::CallerService
      include GH::Domain::Provider::Base

      sig { returns(Stars::Domain) }
      memoize def stars_domain
        Stars::Domain.new(caller_service)
      end
    end
  end
end
