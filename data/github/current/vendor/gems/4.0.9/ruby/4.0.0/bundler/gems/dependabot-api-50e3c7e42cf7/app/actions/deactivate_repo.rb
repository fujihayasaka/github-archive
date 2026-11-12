# frozen_string_literal: true

require "github_helpers"

class DeactivateRepo
  UNKNOWN_USER = { "login" => "unknown", "id" => 0 }.freeze

  attr_reader :account, :repo_github_id, :user

  def initialize(repo_github_id:, account: nil, user: UNKNOWN_USER)
    @account = account
    @repo_github_id = repo_github_id
    @user = user
  end

  def run
    deactivate_update_configs if repo
    delete_repository_access if account
  end

  private

  def deactivate_update_configs
    MetricsClient.increment("repository.deactivated")

    repo.update_configs.active.each do |config|
      Statesman::Machine.retry_conflicts do
        config.transition_to(
          :deleted,
          initiator_github_id: user["id"],
        )
      end
    end
  end

  def delete_repository_access
    RepositoryAccess.delete_by(
      github_id: repo_github_id,
      account_id: account.id
    )
  end

  def repo
    return @repo if defined?(@repo)

    @repo = Repo.find_by(github_id: repo_github_id)
  end
end
