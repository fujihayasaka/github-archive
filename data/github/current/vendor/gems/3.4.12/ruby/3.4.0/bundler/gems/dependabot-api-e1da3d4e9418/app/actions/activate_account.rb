# frozen_string_literal: true

require "github_helpers"

class ActivateAccount
  attr_reader :account, :sender, :installation_id

  class InstallationNotFound < StandardError; end

  def initialize(account:, sender:, installation_id:)
    @account = account
    @sender = sender
    @installation_id = installation_id
  end

  def run
    Statesman::Machine.retry_conflicts do
      if account.in_state?(:inactive)
        # The account is inactive.
        #
        # Attempt to activate it using this installation ID. This attempt will
        # succeed as long as we've never processed this installation ID before
        # (and subsequently disable it).
        activate_account!
      elsif account.current_installation_id == installation_id
        # The account is already active with this installation ID.
        #
        # Ignore the race and just return the current, active account.
        account
      elsif installation_active?(installation_id)
        # The account is active from another installation ID, but this ID is the
        # valid one.
        #
        # We must have missed a webhook about the old installation being
        # disabled. Update the current installation to be this one.
        account.transition_to!(
          :inactive,
          installation_id: account.current_installation_id,
        )
        activate_account!
      else
        # We've been sent an out-of-date installation ID. Ignore it and raise.
        raise InstallationNotFound
      end
    end
  rescue Statesman::TransitionFailedError
    raise unless installation_already_activated?

    account.current_state(force_reload: true)
    account
  end

  private

  def activate_account!
    metadata = {
      initiator_github_id: sender["id"],
    }

    account.transition_to!(
      :active,
      metadata.merge(installation_id: installation_id),
    )

    account
  end

  def installation_active?(installation_id)
    app_github_client.installation(
      installation_id,
      accept: "application/vnd.github.machine-man-preview+json",
    )
    true
  rescue Octokit::NotFound
    false
  end

  def installation_already_activated?
    AccountTransition.exists?(
      to_state: :active,
      most_recent: true,
      installation_id: installation_id,
    )
  end

  def app_github_client
    @app_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(bearer_token: GitHubHelpers.integration_token)
  end
end
