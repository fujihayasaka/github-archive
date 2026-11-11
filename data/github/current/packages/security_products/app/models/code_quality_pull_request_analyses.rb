# typed: strict
# frozen_string_literal: true

class CodeQualityPullRequestAnalyses
  CODE_QUALITY_PULL_REQUEST_ANALYSES_KV_KEY = "code_quality.pull_request_analysis"
  CODE_QUALITY_PULL_REQUEST_ANALYSES_KV_VERSION = "1"
  CODE_QUALITY_PULL_REQUEST_ANALYSES_KV_EXPIRY_DAYS = 90

  COPILOT_ANALYSIS_CONFIGURATION = "copilot"

  class << self
    # We record each analysis configuration in its own entry rather than storing a list of configurations.
    # This helps us avoid losing an analysis configuration due to a race condition: e.g. if we receive two
    # analyses for the same commit very close in time, we might read - read - save - save which would lead
    # to losing the first analysis configuration.
    # This means including the analysis configuration as part of the key, and we don't bother storing a value.
    sig do
      params(
        repository: Repository,
        pull_request: PullRequest,
        commit_oid: String, analysis_configuration: String
      ).void
    end
    def record(repository:, pull_request:, commit_oid:, analysis_configuration:)
      key = kv_store_key(repository_id: repository.id, pull_request_id: pull_request.id, commit_oid:, analysis_configuration:)
      CodeScanning::KV.store.set(key, analysis_configuration, expires: CODE_QUALITY_PULL_REQUEST_ANALYSES_KV_EXPIRY_DAYS.days.from_now)
    end

    sig do
      params(repository: Repository, pull_request: PullRequest, commit_oid: String)
      .returns(T::Array[String])
    end
    def received_analysis_configurations(repository:, pull_request:, commit_oid:)
      key_prefix = kv_store_prefix(repository_id: repository.id, pull_request_id: pull_request.id, commit_oid:)

      analysis_configurations = CodeScanning::KV.store.mget_prefix(key_prefix)&.value!
      if analysis_configurations.present?
        analysis_configurations.values
      else
        []
      end
    end

    sig do
      params(repository: Repository, pull_request: PullRequest, commit_oid: String)
      .returns(T::Boolean)
    end
    def analysis_completed?(repository:, pull_request:, commit_oid:)
      pending_languages(repository:, pull_request:, commit_oid:).empty?
    end

    sig do
      params(repository: Repository, pull_request: PullRequest, commit_oid: String)
      .returns(T::Boolean)
    end
    def copilot_review_completed?(repository:, pull_request:, commit_oid:)
      key = kv_store_key(repository_id: repository.id, pull_request_id: pull_request.id, commit_oid:, analysis_configuration: CodeQualityPullRequestAnalyses::COPILOT_ANALYSIS_CONFIGURATION)
      result = CodeScanning::KV.store.get(key)&.value!
      result.present?
    end

    sig do
      params(repository: Repository, pull_request: PullRequest, commit_oid: String)
      .returns(T::Array[String])
    end
    def pending_languages(repository:, pull_request:, commit_oid:)
      expected_languages = CodeQualityEnablement.new(repository).configuration.languages
      received_configurations = CodeQualityPullRequestAnalyses.received_analysis_configurations(repository:, pull_request:, commit_oid:)

      expected_languages.reject do |language|
        received_configurations.include?("/language:#{language}")
      end
    end

    sig do
      params(repository: Repository, ref: String, commit_oid: String)
      .returns(String)
    end
    def analysis_first_upload_key(repository:, ref:, commit_oid:)
      "code_quality.first_upload_timestamp.#{repository.id}_#{ref}_#{commit_oid}"
    end

    private

    sig do
      params(
        repository_id: Integer,
        pull_request_id: Integer,
        commit_oid: String,
        analysis_configuration: String
      ).returns(String)
    end
    def kv_store_key(repository_id:, pull_request_id:, commit_oid:, analysis_configuration:)
      prefix = kv_store_prefix(repository_id:, pull_request_id:, commit_oid:)
      "#{prefix}:#{analysis_configuration}"
    end

    sig do
      params(
        repository_id: Integer,
        pull_request_id: Integer,
        commit_oid: String
      ).returns(String)
    end
    def kv_store_prefix(repository_id:, pull_request_id:, commit_oid:)
      beginning = "#{CODE_QUALITY_PULL_REQUEST_ANALYSES_KV_KEY}.#{CODE_QUALITY_PULL_REQUEST_ANALYSES_KV_VERSION}"
      "#{beginning}:#{repository_id}:#{pull_request_id}:#{commit_oid}"
    end
  end
end
