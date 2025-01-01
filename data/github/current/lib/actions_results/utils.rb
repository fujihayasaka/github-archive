# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  class Utils

    SYSTEM_LOGS_KEY = "system".freeze
    ACTIONS_RESULTS_URI_SCHEME = "results".freeze
    ACTIONS_RESULTS_URI_REGEX = /results:\/\/actions-results\/run\/(?<workflow_run_backend_id>[A-Fa-f\d-]+)\/job\/(?<workflow_job_run_backend_id>[A-Fa-f\d-]+)(?:\/step\/(?<step_backend_id>[A-Fa-f\d-]+))?/i.freeze

    STATUSES = {
      STATUS_INVALID: nil,
      STATUS_REQUESTED: :requested,
      STATUS_QUEUED: :queued,
      STATUS_IN_PROGRESS: :in_progress,
      STATUS_COMPLETED: :completed,
      STATUS_WAITING: :waiting,
      STATUS_PENDING: :pending,
    }.freeze

    CONCLUSIONS = {
      CONCLUSION_INVALID: nil,
      CONCLUSION_NEUTRAL: :neutral,
      CONCLUSION_SUCCESS: :success,
      CONCLUSION_FAILURE: :failure,
      CONCLUSION_CANCELLED: :cancelled,
      CONCLUSION_ACTION_REQUIRED: :action_required,
      CONCLUSION_TIMED_OUT: :timed_out,
      CONCLUSION_SKIPPED: :skipped,
      CONCLUSION_STALE: :stale,
    }.freeze

    sig { params(url: T.nilable(String)).returns(T::Boolean) }
    def self.is_results_url?(url)
      return false if url.blank?

      # Note: the URI from the results service will have
      # a protocol of results, not https
      uri = URI.parse(url)

      uri.scheme == ACTIONS_RESULTS_URI_SCHEME
    end

    sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
    def self.actions_url(url)
      return nil if url.blank?

      uri = URI.parse(url)
      params = Rack::Utils.parse_query(uri.query)

      return nil unless params["actions_url"]

      CGI.unescape(params["actions_url"])
    end

    sig { params(status: T.nilable(T.any(Symbol, Integer))).returns(T.nilable(Symbol)) }
    def self.to_monolith_status(status)
      status = MonolithTwirp::ActionsResults::Core::V1::Status.lookup(status) if status.is_a?(Integer)
      STATUSES[status]
    end

    sig { params(conclusion: T.nilable(T.any(Symbol, Integer))).returns(T.nilable(Symbol)) }
    def self.to_monolith_conclusion(conclusion)
      conclusion = MonolithTwirp::ActionsResults::Core::V1::Conclusion.lookup(conclusion) if conclusion.is_a?(Integer)
      CONCLUSIONS[conclusion]
    end

    sig { params(status: T.nilable(T.any(String, Symbol))).returns(Symbol) }
    def self.to_results_status(status)
      STATUSES.key(status&.to_sym) || :STATUS_INVALID
    end

    sig { params(conclusion: T.nilable(T.any(String, Symbol))).returns(Symbol) }
    def self.to_results_conclusion(conclusion)
      CONCLUSIONS.key(conclusion&.to_sym) || :CONCLUSION_INVALID
    end

    sig { params(results_url: String).returns(T.nilable(MatchData)) }
    def self.get_ids_from_results_url(results_url)
      results_url.match(ACTIONS_RESULTS_URI_REGEX)
    end

    sig { params(ts: T.nilable(Google::Protobuf::Timestamp)).returns(T.nilable(Time)) }
    def self.pb_to_time(ts)
      return nil if ts.nil?
      return nil if ts.seconds == 0
      Time.at(ts.seconds).utc
    end
  end
end
