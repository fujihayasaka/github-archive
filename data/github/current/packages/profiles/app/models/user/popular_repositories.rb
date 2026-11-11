# typed: true
# frozen_string_literal: true

class User::PopularRepositories
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Public: Returns how many popular repositories will be returned for the user.
  def limit
    6
  end

  def repositories
    user.public_repositories.active.includes(:owner, :mirror, :parent).
         order("watcher_count DESC, created_at ASC").limit(limit)
  end
end
