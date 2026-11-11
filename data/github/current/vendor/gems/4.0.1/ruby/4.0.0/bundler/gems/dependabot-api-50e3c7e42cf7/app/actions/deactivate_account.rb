# frozen_string_literal: true

class DeactivateAccount
  attr_reader :account, :installation_id, :sender, :event_source

  def initialize(account:, installation_id:, sender:, event_source: "unknown")
    @account = account
    @installation_id = installation_id
    @sender = sender
    @event_source = event_source
  end

  def run
    Statesman::Machine.retry_conflicts do
      Dependabot::Exceptions.push("gh.owner.id": account.id)

      deactivate_account! if account.in_state?(:active)

      account
    end
  rescue Statesman::TransitionFailedError, Statesman::GuardFailedError
    current_state = account.reload.current_state
    raise unless current_state == "inactive"

    account
  end

  private

  def deactivate_account!
    account.transition_to!(
      :inactive,
      initiator_github_id: sender["id"],
      installation_id: installation_id,
    )

    DeactivateAccountUpdateConfigs.new(
      account: account,
      user: sender
    ).run

    instrument_account_transition
  end

  def instrument_account_transition
    MetricsClient.increment("account_transition.inactive",
                            tags: {
                              event_source: event_source,
                              repos: account.repos.count,
                            })
  end
end
