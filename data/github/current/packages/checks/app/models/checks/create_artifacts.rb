# typed: true
# frozen_string_literal: true

class Checks::CreateArtifacts
  include GitHub::Tracing

  attr_reader :check_suite, :artifacts

  trace_method(
    :call,
    span_attribute_extractor: -> (instance, *_args, **_kwargs) do
      {
        "gh.repo.id" => instance.check_suite.repository_id,
        "gh.check_suite.id" => instance.check_suite.id,
      }
    end
  )

  def self.call(check_suite:, artifacts:)
    new(
      check_suite: check_suite,
      artifacts: artifacts,
    ).call
  end

  def initialize(check_suite:, artifacts:)
    @check_suite = check_suite
    @artifacts = artifacts
  end

  def call
    return if artifacts.blank?

    existing_source_urls = check_suite.artifacts.distinct.pluck(:source_url)
    new_artifacts = artifacts
      .each do |artifact|
        artifact[:repository_id] = @check_suite.repository_id
        artifact[:workflow_run_id] = @check_suite.workflow_run.id if @check_suite.workflow_run.present?
      end
      # deduplication of artifacts by source_url to make this operation idempotent
      .reject { |artifact| existing_source_urls.include?(artifact[:source_url]) }

    return if new_artifacts.blank?

    new_artifacts.map { |artifact| artifact.merge(check_suite_id: check_suite.id) }.each_slice(100) do |batch|
      Artifact.create(batch)
    end
  end
end
