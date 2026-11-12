# frozen_string_literal: true

class CaptureCompatibilityScoreJob < ApplicationJob
  SHA_REGEX = /^[0-9a-f]{40}$/

  def perform(pull_request)
    return unless computable?(pull_request)

    score = compute_score(pull_request)

    success_count  = score[GitHub::CheckRun::Conclusion::SUCCESS.to_sym].to_i
    failure_count  = score[GitHub::CheckRun::Conclusion::FAILURE.to_sym].to_i

    report_metrics(success_count: success_count, failure_count: failure_count)

    log_compatibility_score(pull_request: pull_request, success_count: success_count, failure_count: failure_count)
  rescue ActiveRecord::QueryCanceled
    log_failure_to_compute(pull_request: pull_request)
  end

  private

  def compute_score(pull_request)
    dependency = pull_request.updated_dependencies.first

    CompatibilityScore.new(
      dependency_name: dependency.name,
      package_manager: dependency.package_manager,
      new_version: dependency.version,
      previous_version: dependency.previous_version
    ).pull_request_counts.with_indifferent_access
  end

  def computable?(pull_request)
    return false if Dependabot.proxima? || Dependabot.enterprise?
    return false unless pull_request.updated_dependencies.one?

    dependency = pull_request.updated_dependencies.first

    dependency.previous_version.present? &&
      !dependency.previous_version.match?(SHA_REGEX)
  end

  def report_metrics(success_count:, failure_count:)
    MetricsClient.gauge(
      "capture_compatibility_score.merged_pr.compatibility_score",
      compatibility_score(success_count: success_count, failure_count: failure_count)
    )
  end

  def log_compatibility_score(pull_request:, success_count:, failure_count:)
    Dependabot::Logger.info(
      msg: "Compatibility Score at time of merge",
      pull_request: pull_request.id,
      "gh.pull_request.number": pull_request.github_number,
      "gh.repo.id": pull_request.update_config.repo.github_id,
      private: pull_request.update_config.repo.private,
      compatibility_score: compatibility_score(success_count: success_count, failure_count: failure_count),
      successes: success_count,
      candidates: success_count + failure_count,
    )
  end

  def log_failure_to_compute(pull_request:)
    Dependabot::Logger.error(
      msg: "Compatibility score took too long to compute",
      pull_request: pull_request,
    )
  end

  def compatibility_score(success_count:, failure_count:)
    return -1 if success_count + failure_count < 5

    numerator = success_count
    denominator = success_count + failure_count

    numerator.to_f / denominator
  end
end
