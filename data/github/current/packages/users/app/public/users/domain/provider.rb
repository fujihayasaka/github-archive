# typed: strict
# frozen_string_literal: true

module Users
  class Domain
    module Provider
      extend T::Sig
      extend T::Helpers

      requires_ancestor { Kernel }

      include GitHub::Memoizer
      include GH::Domain::CallerService
      include GH::Domain::Provider::Base

      # Feel free to override this method so the domain can get a handle on the current actor.
      sig { returns(T.nilable(GH::Auth::Actor)) }
      def domain_actor; end

      sig { returns(Users::Domain) }
      memoize def users_domain
        Users::Domain.new(caller_service, actor: domain_actor)
      end
    end
  end
end
