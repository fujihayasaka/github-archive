# typed: strict
# frozen_string_literal: true

module Webhooks
  module IHook

    extend T::Helpers

    include Kernel

    requires_ancestor { Object }

    abstract!

    InstallationTargetTypes = T.type_alias { T.any(Repository, User, Business, Integration, Marketplace::Listing, SponsorsListing) }

    sig { abstract.returns(T::Boolean) }
    def repo_hook?; end

    sig { abstract.returns(InstallationTargetTypes) }
    def installation_target; end
  end
end
