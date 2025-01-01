# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module RepositoriesSerializer
    extend T::Helpers
    extend T::Sig

    include UrlHelpers

    sig { params(repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_repository(repository:)
      {
        ownerLogin: repository.owner_display_login,
        name: repository.name,
        path: repository_path(repository),
        typeIcon: repository.repo_type_icon,
      }
    end
  end
end
