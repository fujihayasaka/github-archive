# typed: strict
# frozen_string_literal: true

module Marketplace
  module Repositories
    class Contributors
      include T::Helpers
      include AvatarHelper

      CONTRIBUTOR_LIMIT = 14
      private_constant :CONTRIBUTOR_LIMIT

      sig { returns(Repository) }
      attr_reader :repository

      sig { returns(T.nilable(User)) }
      attr_reader :user

      sig { params(repository: Repository, user: T.nilable(User)).void }
      def initialize(repository, user)
        @repository = repository
        @user = user
      end

      sig { returns(Integer) }
      def total_count
        CommitContribution.contributors_count_for_repository(repository)
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def top_contributors_data
        top_contributors.map do |contributor|
          {
            src: avatar_url_for(contributor, 64),
            alt: alt_text(contributor),
            displayLogin: contributor.display_login
          }
        end
      end

      private

      sig { returns(T::Array[User]) }
      def top_contributors
        repository.top_contributors(
          limit: CONTRIBUTOR_LIMIT,
          viewer: user,
          skip_private_profiles: true,
        )
      end
    end
  end
end
