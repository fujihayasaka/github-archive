# typed: true
# frozen_string_literal: true

class CommitUploadManifestJobStatus < ::JobStatus
  include ::JobStatus::Context

  sig { returns(String) }
  attr_reader :id

  sig { returns(String) }
  attr_reader :state

  sig { returns(T.nilable(String)) }
  attr_reader :error_message

  sig { returns(T.nilable(Integer)) }
  attr_reader :uploader_id

  sig { returns(T.nilable(T::Array[RuleEngine::RuleRun])) }
  attr_reader :failed_runs

  ID_PREFIX = "commit_upload_manifest"

  sig do
    override
      .params(attributes: T::Hash[Symbol, T.untyped])
      .void
  end
  def initialize(attributes = {})
    super(attributes)
    @failed_runs = attributes[:failed_runs]
    @uploader_id = attributes[:uploader_id]
  end

  sig do
    override
      .params(attributes: T::Hash[Symbol, T.untyped])
      .returns(CommitUploadManifestJobStatus)
  end
  def self.create(attributes = {})
    super(attributes.merge(id: job_id(attributes[:id])))
  end

  sig do
    override
      .params(
        message: T.nilable(String),
        failed_runs: T::Array[RuleEngine::RuleRun],
        ttl: ActiveSupport::Duration
      )
      .void
  end
  def error!(message = nil, failed_runs = [], ttl: DEFAULT_COMPLETED_JOB_TTL)
    @failed_runs = failed_runs
    super(message, ttl: ttl)
  end

  sig do
    params(manifest_id: T.nilable(Integer))
    .returns(String)
  end
  def self.job_id(manifest_id)
    [ID_PREFIX, manifest_id].join("_")
  end

  def as_json
    {
      id: id,
      state: state,
      ttl: ttl,
      error_message: error_message,
      failed_runs: failed_runs,
      uploader_id: uploader_id
    }
  end

  def to_json
    as_json.to_json(
      only: [
        :id,
        :state,
        :error_message,
        :failed_runs,
        :uploader_id,
        :rule_type,
        :rule_provider,
        :result,
        :repository_rule_configuration_id,
        :message,
        :violations,
        :evaluation_metadata
      ]
    )
  end
end
