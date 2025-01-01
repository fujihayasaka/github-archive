# typed: strict
# frozen_string_literal: true

class BlackbirdOnboardJob < ApplicationJob
  extend T::Sig

  queue_as :blackbird
  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 4

  sig { params(user_logins: T::Array[String]).void }
  def perform(user_logins)
    # NOTE: May be either a user or an organization.
    owners = User.where(login: user_logins)

    # Onboard all thee repos for each owner
    owners.each do |owner|
      onboard_repos(account: owner)
    end
  end

  # Onboard all repositories owned by a user/org to be indexed for blackbird
  # code search.
  sig { params(account: User).void }
  def onboard_repos(account:)
    account.repositories.each do |repo|
      GlobalInstrumenter.instrument("blackbird.repository.onboard",
        repository: repo,
      )
    end
  end
end
