# typed: strict
# frozen_string_literal: true

module Dashboard
  class Domain
    module Provider
      extend T::Sig
      extend T::Helpers

      include Kernel
      include GitHub::Memoizer
      include GH::Domain::CallerService
      include GH::Domain::Provider::Base

      sig { returns(Dashboard::Domain) }
      memoize def dashboard_domain
        Dashboard::Domain.new(caller_service)
      end
    end
  end
end
