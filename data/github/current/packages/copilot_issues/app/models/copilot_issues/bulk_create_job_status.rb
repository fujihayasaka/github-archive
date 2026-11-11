# typed: true
# frozen_string_literal: true

module CopilotIssues
  class BulkCreateJobStatus < ::JobStatus
    CACHE_KEY_PREFIX = T.let("copilot-issues-bulk-create", String)
    QUEUED_JOB_TTL = T.let(3.minutes, ActiveSupport::Duration)
    DEFAULT_JOB_TTL = T.let(10.minutes, ActiveSupport::Duration)

    # Setting a max limit based on the existing GraphQL limit
    MAX_ISSUE_WRITES = T.let(60, Integer)

    class ContinuableError < T::Struct
      const :message, String
      const :type, String

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def as_json
        {
          message: message,
          type: type,
        }
      end
    end

    class IssueIdentifiers < T::Struct
      const :tag, String
      const :id, Integer
      const :number, Integer
      const :href, String
      const :repository_id, Integer
      const :errors, T::Array[ContinuableError]
    end

    sig { returns(T::Array[IssueIdentifiers]) }
    attr_reader :completed_issues

    sig { returns(Integer) }
    attr_reader :percentage

    sig { returns(Time) }
    attr_reader :updated_at

    sig { params(attributes: T::Hash[T.untyped, T.untyped]).void }
    def initialize(attributes = {})
      super(attributes)
      @updated_at = T.let((attributes[:updated_at] || Time.now).to_time, Time)
      @percentage = T.let((attributes[:percentage] || 0).to_i, Integer)
      @completed_issues = T.let([], T::Array[IssueIdentifiers])

      if attributes[:completed_issues]
        attributes[:completed_issues].each do |issue|
          issue = issue.with_indifferent_access
          errors = nil
          if issue[:errors]
            errors = issue[:errors].map do |error_hash|
              error = error_hash.with_indifferent_access
              ContinuableError.new(
                message: error[:message],
                type: error[:type]
              )
            end
          end

          @completed_issues << IssueIdentifiers.new(
            tag: issue[:tag],
            id: issue[:id],
            href: issue[:href],
            number: issue[:number],
            repository_id: issue[:repository_id],
            errors: errors,
          )
        end
      end
    end

    sig { params(id: String).returns(BulkCreateJobStatus) }
    def self.create(id:)
      # Set a short initial TTL to prevent polling for too long if job fails immediately
      super(ttl: QUEUED_JOB_TTL, id: "#{CACHE_KEY_PREFIX}-#{id}")
    end

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      id.start_with?(CACHE_KEY_PREFIX)
    end

    sig { params(id: String, meta: T::Hash[Symbol, T.untyped]).returns(T.nilable(BulkCreateJobStatus)) }
    def self.find(id, meta: {})
      if id.start_with?(CACHE_KEY_PREFIX)
        super(id)
      else
        super("#{CACHE_KEY_PREFIX}-#{id}")
      end
    end

    sig { returns(GitHub::KV) }
    def self.kv_store
      Copilot::KV.store
    end

    sig { override.void }
    def started!
      # Update TTL back to the default once the job starts
      self.ttl = DEFAULT_JOB_TTL
      super
    end

    sig { override.params(ttl: ActiveSupport::Duration).void }
    def success!(ttl: DEFAULT_COMPLETED_JOB_TTL)
      @percentage = 100
      super(ttl: ttl)
    end

    sig { params(issue_identifiers: IssueIdentifiers).void }
    def add_completed_issues(issue_identifiers)
      @completed_issues << issue_identifiers
      save
    end

    sig { params(tag: String, errors: T::Array[ContinuableError]).void }
    def add_continuable_errors(tag, errors)
      issue = @completed_issues.find { |i| i.tag == tag }
      return unless issue

      issue.errors.concat(errors)
      save
    end

    sig { params(percentage: Integer).void }
    def set_percentage(percentage)
      @percentage = percentage
      save
    end

    sig { void }
    def save
      @updated_at = Time.now
      super
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def as_json
      super.merge({
        percentage: percentage,
        updated_at: updated_at.to_s,
        completed_issues: completed_issues.map { |issue| issue.as_json },
      })
    end
  end
end
