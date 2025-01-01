# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    module Provider
      extend T::Sig
      extend T::Helpers

      include Kernel
      include GitHub::Memoizer
      include GH::Domain::CallerService
      include GH::Domain::Provider::Base

      sig { returns(Issues::Domain) }
      memoize def issues_domain
        Issues::Domain.new(caller_service)
      end
    end
  end
end
