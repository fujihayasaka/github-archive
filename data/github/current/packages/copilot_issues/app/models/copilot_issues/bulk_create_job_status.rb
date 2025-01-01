# typed: true
# frozen_string_literal: true

module CopilotIssues
  class BulkCreateJobStatus < ::JobStatus
    include ::JobStatus::Context

    PREFIX = "copilot-issues-bulk-create"
    QUEUED_JOB_TTL = T.let(1.minute, ActiveSupport::Duration)
    DEFAULT_JOB_TTL = T.let(10.minutes, ActiveSupport::Duration)

    sig { returns(T::Array[Integer]) }
    attr_reader :completed_issue_ids

    sig { returns(T::Array[String]) }
    attr_reader :completed_issue_urls

    sig { params(attributes: T::Hash[T.untyped, T.untyped]).void }
    def initialize(attributes = {})
      super(attributes)
      @percentage = T.let(attributes[:percentage] || 0, Integer)
      @completed_issue_ids = T.let(attributes[:completed_issue_ids] || [], T::Array[Integer])
      @completed_issue_urls = T.let(attributes[:completed_issue_urls] || [], T::Array[String])
      @execution_errors = T.let(attributes[:execution_errors] || [], T::Array[T.untyped])
      @updated_at = T.let(attributes[:updated_at] || Time.now, Time)
    end

    sig { params(id: String, attributes: T::Hash[T.untyped, T.untyped]).returns(T.attached_class) }
    def self.create(id:, attributes: {})
      super(id: "#{PREFIX}-#{id}", **attributes)
    end

    sig { params(id: String).returns(T.nilable(JobStatus)) }
    def self.find(id)
      if id.start_with?(PREFIX)
        super(id)
      else
        super("#{PREFIX}-#{id}")
      end
    end

    def self.kv_store
      JobStatus::KV.store
    end

    sig { params(percentage: Integer).void }
    def set_percentage(percentage)
      @percentage = percentage
      save
    end

    sig { params(issue_id: Integer).void }
    def add_completed_issue_id(issue_id)
      completed_issue_ids << issue_id
      save
    end

    sig { params(issue_url: String).void }
    def add_completed_issue_urls(issue_url)
      completed_issue_urls << issue_url
      save
    end

    def success!
      @percentage = 100
      super
    end


    # TODO - add more methods to handle job status updates, errors, etc.
  end
end
