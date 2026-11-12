# frozen_string_literal: true

# Detects whether the dependency files referenced by a PullRequest's update
# config have changed on the PR's base branch since the PR was created.
#
# Extracted from CheckPullRequestForConflictsJob to keep the job focused on
# orchestration. The compare API call is invoked from #changed?; callers are
# responsible for any surrounding instrumentation/error handling.
class PullRequestDependencyChangeDetector
  def initialize(pull_request:, github_details:, github_client:)
    @pull_request = pull_request
    @github_details = github_details
    @github_client = github_client
  end

  def changed?
    result = changed_dependency_files.any? do |file|
      pull_request.updated_dependencies.any? do |dep|
        # Some dependencies use mixed-case in their names, so we call `downcase`
        # here to make sure they don't get ignored.
        file.patch.to_s.downcase.include?(dep.name.downcase)
      end
    end
    instrument_pr_age(false, result)
    result
  rescue Octokit::UnprocessableEntity => e
    raise unless e.message.include?("this diff is taking too long")

    handle_diff_too_long(e)
    false # We don't know for certain, so we return false
  end

  private

  attr_reader :pull_request

  def changed_dependency_files
    files_changed_since_pr_created.select do |file|
      UpdateConfig.path_matches_updated_files_regex?(file_regexes, file.filename)
    end
  end

  def file_regexes
    @file_regexes ||= EcosystemFileRegex.new(@pull_request.update_config.package_manager).updated_files_regex
  end

  def files_changed_since_pr_created
    @github_client.compare(
      pull_request.repo.github_id,
      @github_details.base.sha,
      @github_details.base.ref,
    ).files
  end

  def handle_diff_too_long(error)
    Dependabot::Logger.error(msg: "diff took too long",
                             "code.namespace": "pull_request_dependency_change_detector",
                             "exception.message": error.message,
                             **pull_request.telemetry_attributes)
    instrument_pr_age(true)
  end

  def instrument_pr_age(errored, changed = nil)
    MetricsClient.gauge("pull_request_dependency_change_detector.pr_age_in_days",
                        pull_request.age_in_days,
                        tags: {
                          changed: changed,
                          errored: errored,
                        })
  end
end
