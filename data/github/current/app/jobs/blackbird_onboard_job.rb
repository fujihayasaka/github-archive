# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class BlackbirdOnboardJob < ApplicationJob
  queue_as :blackbird
  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 4

  sig { params(users: T::Array[User]).void }
  def perform(users)
    # NOTE: May be either a user or an organization.
    # Onboard all thee repos for each owner
    users.each do |owner|
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
