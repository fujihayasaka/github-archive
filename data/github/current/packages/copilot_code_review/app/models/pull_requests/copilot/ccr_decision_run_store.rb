# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CcrDecisionRunStore
      class DecisionRun < T::Struct
        const :response_request_id, String
        const :pull_request_id, Integer
        const :repository_id, Integer
        const :pull_request_review_id, Integer
        const :submitted_at, Time
        const :head_sha, T.nilable(String)
        const :approval_readiness_code, T.nilable(String)
        const :review_submission_event, String
        const :experiment_assignment_context, T.nilable(String)
        const :decision_assessment_required, T::Boolean, default: false
      end

      KEY_PREFIX = T.let("copilot:code-review:ccr-decision-run".freeze, String)

      sig do
        params(
          response_request_id: String,
          pull_request_id: Integer,
          repository_id: Integer,
          pull_request_review_id: Integer,
          submitted_at: Time,
          head_sha: T.nilable(String),
          review_submission_event: String,
          approval_readiness_code: T.nilable(String),
          experiment_assignment_context: T.nilable(String),
          decision_assessment_required: T::Boolean,
        ).void
      end
      def self.record(
        response_request_id:,
        pull_request_id:,
        repository_id:,
        pull_request_review_id:,
        submitted_at:,
        head_sha:,
        review_submission_event:,
        approval_readiness_code: nil,
        experiment_assignment_context: nil,
        decision_assessment_required: false
      )
        payload = {
          response_request_id: response_request_id,
          pull_request_id: pull_request_id,
          repository_id: repository_id,
          pull_request_review_id: pull_request_review_id,
          submitted_at: submitted_at.iso8601,
          head_sha: head_sha,
          approval_readiness_code: approval_readiness_code,
          review_submission_event: review_submission_event,
          experiment_assignment_context: experiment_assignment_context,
          decision_assessment_required: decision_assessment_required,
        }.compact.to_json

        ::Copilot::KV.store.set(review_key(pull_request_review_id), payload)
        ::Copilot::KV.store.set(pull_request_run_key(pull_request_id, pull_request_review_id), payload)
      end

      sig { params(pull_request_id: Integer).returns(T::Array[DecisionRun]) }
      def self.runs_for_pull_request(pull_request_id:)
        values_for_pull_request(pull_request_id)
          .values
          .filter_map { |value| parse_run(value) }
          .sort_by { |run| [run.submitted_at, run.pull_request_review_id] }
      end

      sig { params(pull_request_review_id: Integer).returns(T.nilable(DecisionRun)) }
      def self.run_for_pull_request_review_id(pull_request_review_id:)
        stored_value = value_for(review_key(pull_request_review_id))
        return nil if stored_value.blank?

        parse_run(stored_value)
      end

      sig { params(pull_request_id: Integer).returns(T::Hash[String, String]) }
      def self.values_for_pull_request(pull_request_id)
        ::Copilot::KV.store.mget_prefix(pull_request_runs_prefix(pull_request_id)).value { {} }
      end

      sig { params(value: String).returns(T.nilable(DecisionRun)) }
      def self.parse_run(value)
        parsed = JSON.parse(value)
        return nil unless parsed.is_a?(Hash)

        DecisionRun.new(
          response_request_id: parsed.fetch("response_request_id"),
          pull_request_id: Integer(parsed.fetch("pull_request_id")),
          repository_id: Integer(parsed.fetch("repository_id")),
          pull_request_review_id: Integer(parsed.fetch("pull_request_review_id")),
          submitted_at: Time.iso8601(parsed.fetch("submitted_at")),
          head_sha: parsed["head_sha"],
          approval_readiness_code: parsed["approval_readiness_code"],
          review_submission_event: parsed.fetch("review_submission_event"),
          experiment_assignment_context: parsed["experiment_assignment_context"],
          decision_assessment_required: parsed.fetch("decision_assessment_required", false) == true,
        )
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError
        nil
      end

      sig { params(key: String).returns(T.nilable(String)) }
      def self.value_for(key)
        ::Copilot::KV.store.get(key).value { nil }
      end

      sig { params(pull_request_review_id: Integer).returns(String) }
      def self.review_key(pull_request_review_id)
        "#{KEY_PREFIX}:pull-request-review:#{pull_request_review_id}"
      end

      sig { params(pull_request_id: Integer, pull_request_review_id: Integer).returns(String) }
      def self.pull_request_run_key(pull_request_id, pull_request_review_id)
        "#{pull_request_runs_prefix(pull_request_id)}#{pull_request_review_id}"
      end

      sig { params(pull_request_id: Integer).returns(String) }
      def self.pull_request_runs_prefix(pull_request_id)
        "#{KEY_PREFIX}:pull-request:#{pull_request_id}:pull-request-review:"
      end

      private_class_method :parse_run, :pull_request_run_key, :pull_request_runs_prefix, :review_key, :value_for, :values_for_pull_request
    end
  end
end
