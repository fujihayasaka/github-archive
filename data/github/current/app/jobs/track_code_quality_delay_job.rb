# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TrackCodeQualityDelayJob < ApplicationJob
  COMPLETION_TIME_TARGET = 5.minutes

  queue_as :code_quality

  before_perform do |job|
    context = {
      job: job.class.name,
      repository: job.arguments.first,
      ref: job.arguments.second,
      commit_oid: job.arguments.third,
    }
    Failbot.push(context)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository, ref, commit_oid)

    matcher = ref&.match(/\Arefs\/pull\/([0-9]+)\/(head|merge)\Z/)
    pull_request = nil
    if matcher
      pr_number = matcher[1]
      pull_request = PullRequest.with_number_and_repo(pr_number, repository)
    end

    return if pull_request.nil?

    completed = CodeQualityPullRequestAnalyses.analysis_completed?(repository: repository, pull_request: pull_request, commit_oid: commit_oid)

    GitHub.dogstats.increment("code_quality.target_time_elapsed", tags: ["completed:#{completed}"])
    GitHub.logger.info(
      "Code Quality Analysis target time elapsed.",
      "code.namespace" => "TrackCodeQualityDelayJob",
      "code.function" => "perform",
      "gh.repo.id" => repository.id,
      "gh.completed" => completed,
      "gh.ref" => ref,
      "gh.commit_oid" => commit_oid,
      "gh.pull_request_id" => pull_request.id
    )
  end

  def self.schedule(repository, ref, commit_oid)
    set(wait: COMPLETION_TIME_TARGET).perform_later(repository, ref, commit_oid)
  end
end
