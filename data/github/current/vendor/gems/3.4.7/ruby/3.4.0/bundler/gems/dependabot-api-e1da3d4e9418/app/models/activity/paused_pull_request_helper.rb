# frozen_string_literal: true

# TODO: Remove this helper once the cleanup transition has been executed
#
# See: https://github.com/github/dependabot-updates/issues/3492
module Activity
  class PausedPullRequestHelper
    PAUSED_PR_LIMIT = 100

    def initialize(repo:, client:)
      @repo = repo
      @client = client
    end

    def remove_paused_label
      # attempt to remove the label, but don't fail if it doesn't exist
      client.delete_label!(repo.github_id, Repo::PAUSED_LABEL)
    rescue Octokit::NotFound
      # noop
    end

    def open_dependabot_prs
      # A single repository can have 100N open PRs in the most extreme case where:
      # - N is the `open_pull_request_limit` they have set on each update config
      # - 100 is the maximum number of update configs we let them configure
      #
      # We limit the maximum number of PRs we will update to avoid extreme cases
      # where a user has `open_pull_request_limit` of 999 on an abandoned repo.
      @open_dependabot_prs ||= repo.pull_requests.open.order(id: :desc).limit(PAUSED_PR_LIMIT)
    end

    def remove_paused_edit(pull_request)
      pr_detail = open_dependabot_pr_details.find { |detail| detail.number == pull_request.github_number }

      return unless pr_detail
      return if pr_detail.state == "closed"

      regex = %r{\[//\]: # \(dependabot-start\).*\[//\]: # \(dependabot-end\)}m
      updated_body = pr_detail.body.gsub(regex, "").strip

      UpdatePullRequestBody.new(pull_request: pull_request, updated_body: updated_body).run
    end

    private

    attr_reader :repo, :client

    def open_dependabot_pr_details
      headers = { accept: "application/vnd.github.machine-man-preview+json" }
      options = { per_page: 100, state: "open" }.merge(headers)

      @open_dependabot_pr_details ||=
        GitHubHelpers.fetch_all_pages(
          client: client,
          method: :pull_requests,
          args: [repo.github_id, options],
          headers: headers,
          transform: lambda do |p|
            p.data.select { |pr| open_dependabot_pr_numbers.include?(pr.number) }
          end,
        )
    end

    def open_dependabot_pr_numbers
      open_dependabot_prs.map(&:github_number)
    end
  end
end
