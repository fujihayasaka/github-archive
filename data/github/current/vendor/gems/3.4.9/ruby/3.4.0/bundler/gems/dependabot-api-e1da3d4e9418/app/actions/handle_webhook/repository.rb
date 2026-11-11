# frozen_string_literal: true

module HandleWebhook
  class Repository
    attr_reader :webhook_body

    def initialize(webhook_body:)
      @webhook_body = webhook_body
    end

    def run
      Dependabot::Logger.log_context(webhook_context_params) do
        # Saves calling GitHub if this webhook is out-of-date
        if account.blank?
          Dependabot::Logger.info(msg: "Account not found")
          return
        elsif !account.active?
          Dependabot::Logger.info(msg: "Account not active")
          return
        end

        case webhook_body[:action]
        when "deleted", "archived" then deactivate_repo
        when "created", "unarchived" then enqueue_repo_setup
        when "edited", "renamed" then update_repo
        when "publicized" then delete_repository_access
        when "transferred" then handle_transfer
        end
      end
    end

    private

    def webhook_context_params
      {
        "code.namespace": "handle_webhook.repository",
        "gh.repo.id": webhook_body.dig(:repository, :id),
        "gh.owner.id": webhook_body.dig(:repository, :owner, :id),
        "gh.installation.id": webhook_body.dig(:installation, :id),
        "gh.webhook.action": webhook_body[:action],
      }
    end

    def deactivate_repo
      DeactivateRepoJob.perform_later(
        account: account,
        repo_github_id: webhook_body[:repository][:id],
        user: {
          "login" => webhook_body[:sender][:login],
          "id" => webhook_body[:sender][:id],
        },
      )
    end

    def enqueue_repo_setup
      SetupRepoJob.perform_later(
        account: account,
        github_id: webhook_body[:repository][:id],
      )
      Dependabot::Logger.info(msg: "Enqueued repo setup")
    end

    def update_repo
      return enqueue_repo_setup unless repo

      SynchronizeRepoStateJob.perform_later(
        repo: repo,
        event_source: "handle_webhook.repository",
      )
    end

    def handle_transfer
      if repo
        TransferRepoAccountJob.perform_later(repo: repo, new_account: account)
      else
        enqueue_repo_setup
      end

      delete_repository_access
    end

    def delete_repository_access
      RepositoryAccess.delete_by(
        github_id: webhook_body[:repository][:id],
      )
    end

    def repo
      @repo ||= Repo.find_by(github_id: webhook_body[:repository][:id])
    end

    def account
      @account ||=
        if %w(transferred edited renamed).include?(webhook_body[:action])
          Account.find_by(
            github_id: webhook_body[:repository][:owner][:id],
            account_type: account_type,
          )
        elsif webhook_body[:installation]
          Account.
            joins(:account_transitions).
            find_by(
              account_transitions: {
                most_recent: true,
                installation_id: webhook_body[:installation][:id],
              },
            )
        elsif repo&.account&.github_id == webhook_body.dig(:repository, :owner, :id)
          repo.account
        end
    end

    def account_type
      case webhook_body[:repository][:owner][:type]
      when "User" then "user"
      when "Organization" then "org"
      end
    end
  end
end
