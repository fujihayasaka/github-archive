# typed: strict
# frozen_string_literal: true

module Repos::ForkFormHelper
  sig { params(user: User, repo: Repository).returns(T::Array[Repository]) }
  def self.all_existing_forks(user, repo)

    orgs = T.cast(user.organizations.by_login.to_a, T::Array[Organization]).select do |org|
      org.fork_allowed?(repo: repo, user: user) && org.can_create_repository?(user, visibility: repo.visibility)
    end

    forks = repo.network&.repositories&.where(owner: orgs).to_a

    existing_user_fork = T.cast(user.my_fork_of(repo), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    forks.unshift(existing_user_fork) if existing_user_fork

    forks - [repo]
  end
end
