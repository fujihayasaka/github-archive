# frozen_string_literal: true

module HandleWebhook
  class CheckRun
    attr_reader :webhook_body

    def initialize(webhook_body:)
      @webhook_body = webhook_body
    end

    def run
      return unless rerequested? && repo

      ValidateConfigFileJob.perform_later(
        account: repo.account,
        repo_github_id: repo.github_id,
        sha: sha
      )
    end

    private

    def rerequested?
      webhook_body[:action] == "rerequested"
    end

    def repo
      Repo.find_by(github_id: webhook_body[:repository][:id])
    end

    def sha
      webhook_body[:check_run][:head_sha]
    end
  end
end
