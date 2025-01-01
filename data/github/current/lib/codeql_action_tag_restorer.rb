# typed: true
# frozen_string_literal: true

require "github/bound_retry"

class CodeQLActionTagRestorer
  RETRY_LIMIT = 5

  def self.retryable_errors
    [SpokesAPI::TwirpServerError, SpokesAPI::TwirpConnectionError]
  end

  def self.find_repository
    codeql_action_repo_name = "#{github_org_name}/codeql-action"
    repository = Repository.nwo(codeql_action_repo_name)
  end

  def self.github_org_name
    ENV.fetch("ENTERPRISE_ACTIONS_GITHUB_ORG")
  end

  def self.restore_tags
    GitHub::Logger.info "Restoring tags to CodeQL Action repository..."
    repository = find_repository
    if repository.nil?
      GitHub::Logger.info "Exiting as there is no CodeQL Action repository."
      return
    end
    GitHub::Logger.info "Restoring release tags to #{repository.nwo}..."
    repository.releases.each do |release|
      GitHub::Logger.info "Restoring tag #{release.tag_name}..."
      restore_single_tag(repository, release)
    end
  end

  def self.restore_single_tag(repository, release)
    on_exception = proc do |exception, retry_count|
      GitHub::Logger.warn(
        "Transient error while restoring tag #{release.tag_name} (attempt #{retry_count}/#{RETRY_LIMIT}): " \
        "#{exception.class}: #{exception.message}. Retrying with exponential backoff..."
      )
      sleep(2**(retry_count))
    end

    GitHub::BoundRetry.with_bound_retry(*retryable_errors, limit: RETRY_LIMIT, on_exception: on_exception) do
      if repository.refs.find(release.target_commitish).nil?
        GitHub::Logger.info "Target commitish #{release.target_commitish} does not exist, so tagging the default branch instead..."
        release.update(target_commitish: repository.default_branch)
      end
      release.create_tag_on_publish
    end
  end
end
