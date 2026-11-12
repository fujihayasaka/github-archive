# frozen_string_literal: true

require "github_helpers"

class CreateVersionSkipComment
  attr_reader :pull_request

  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    return unless pull_request.repo.account.active?
    return grouped_update_comment_text if pull_request.grouped_update?
    return if ignore_or_skip_requested_previously?

    create_version_skip_comment
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.create_version_skip_comment",
    ).run
  end

  private

  # TODO: Add ignore command hint to the below comment_text once
  # the ignore/unignore commands are implemented for grouped updates.
  def grouped_update_comment_text
    link = "https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/" \
            "configuration-options-for-the-dependabot.yml-file#ignore"
    comment_text = "This pull request was built based on a group rule. " \
                    "Closing it will not ignore any of these versions in future pull requests.\n\n" \
                    "To ignore these dependencies, configure [ignore rules](#{link}) in dependabot.yml"

    CreateComment.new(
      pull_request: pull_request,
      comment_body: comment_text,
    ).run
  end

  def ignore_or_skip_requested_previously?
    skip_msg = "OK, I won't notify you again about this release, but will " \
               "get in touch when a new version is available."
    ignore_msg = "OK, I won't notify you about"

    return true if all_pr_comments.any? { |c| c.body.include?(skip_msg) }

    last_comment = all_pr_comments.last
    return false unless last_comment&.body
    return true if last_comment.body.include?(ignore_msg)

    [
      HandleWebhook::IssueComment::IGNORE_SINGLE_DEP_VALIDATION_REGEX,
      HandleWebhook::IssueComment::IGNORE_MULTIPLE_DEPS_VALIDATION_REGEX,
      HandleWebhook::IssueComment::CLOSE_REGEX,
    ].any? { |r| last_comment.body.gsub(/\.\s/, ".\n").match?(r) }
  end

  def create_version_skip_comment
    CreateComment.new(
      pull_request: pull_request,
      comment_body: comment_text,
    ).run
  end

  def comment_text
    msg = "OK, I won't notify you again about this release, but will get " \
          "in touch when a new version is available."

    if pull_request.single_dependency? &&
       numeric_version?(pull_request.updated_dependencies.first.version)
      msg += " If you'd rather skip all updates until the next major or " \
             "minor version, let me know by commenting `@dependabot ignore " \
             "this major version` or `@dependabot ignore this minor version`."
    end

    if pull_request.repo.using_config_file?
      msg += " You can also ignore all major, minor, or patch releases for a " \
             "dependency by adding an [`ignore` condition]" \
             "(https://docs.github.com/en/code-security/supply-chain-security/" \
             "configuration-options-for-dependency-updates#ignore) " \
             "with the desired `update_types` to your config file."
    end

    msg + "\n\nIf you change your mind, just re-open this PR and I'll " \
          "resolve any conflicts on it."
  end

  def all_pr_comments
    installation_github_client.issue_comments(
      pull_request.repo.github_id,
      pull_request.github_number,
      per_page: 100,
    )
  end

  def numeric_version?(version)
    return false if version.blank?

    Gem::Version.correct?(version)
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end
end
