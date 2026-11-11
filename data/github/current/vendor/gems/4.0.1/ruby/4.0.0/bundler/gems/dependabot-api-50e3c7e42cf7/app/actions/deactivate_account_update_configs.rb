# frozen_string_literal: true

class DeactivateAccountUpdateConfigs
  attr_reader :account, :user

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def run
    # Return early if the account is still active
    return if account.active?

    account.repos.each do |repo|
      repo.update_configs.active.each do |config|
        Statesman::Machine.retry_conflicts do
          config.transition_to(
            :deleted,
            initiator_github_id: user["id"],
          )
        end
      end
    end
  end
end
