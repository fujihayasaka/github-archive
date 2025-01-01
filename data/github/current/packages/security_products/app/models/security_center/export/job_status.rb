# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Export
    class JobStatus < ::JobStatus
      include ::JobStatus::Context

      PREFIX = "security-center-export"

      QUEUED_JOB_TTL = T.let(1.minute, ActiveSupport::Duration)
      DEFAULT_JOB_TTL = T.let(10.minutes, ActiveSupport::Duration)

      sig do
        params(
          id: String,
          query: String,
          requested_at: T.nilable(Time),
          requester: User,
          scope: T.any(Organization, Business),
          start_date: T.nilable(::Date),
          end_date: T.nilable(::Date),
          kwargs: T.untyped,
        ).returns(JobStatus)
      end
      def self.create(id:, query:, requested_at:, requester:, scope:, start_date: nil, end_date: nil, **kwargs)
        raise ArgumentError, "Providing a context is not supported" if kwargs.key?(:context)

        requested_at ||= Time.now
        context = {
          query:,
          scope_id: scope.id,
          scope_type: scope.class.name,
          requester_id: requester.id,
          requested_at: requested_at.dup.utc,
          start_date:,
          end_date:,
        }

        # Set a short initial TTL to prevent polling for too long if job fails immediately
        super(ttl: QUEUED_JOB_TTL, **kwargs, id: "#{PREFIX}-#{id}", context:)
      end

      sig { override.params(ttl: ActiveSupport::Duration).void }
      def success!(ttl: DEFAULT_COMPLETED_JOB_TTL)
        super(ttl: 3.days)
      end

      sig { override.void }
      def started!
        # Update TTL back to the default once the job starts
        self.ttl = DEFAULT_JOB_TTL
        super
      end

      sig { params(id: String).returns(T.nilable(JobStatus)) }
      def self.find(id)
        super("#{PREFIX}-#{id}")
      end

      sig { returns(String) }
      def query
        T.must(context)[:query]
      end

      sig { returns(Integer) }
      def requester_id
        T.must(context)[:requester_id]
      end

      sig { returns(Integer) }
      def scope_id
        T.must(context)[:scope_id]
      end

      sig { returns(String) }
      def scope_type
        T.must(context)[:scope_type]
      end

      sig { returns(String) }
      def requested_at
        T.must(context)[:requested_at].to_s
      end

      sig { returns(T.nilable(String)) }
      def start_date
        T.must(context)[:start_date]&.to_s
      end

      sig { returns(T.nilable(String)) }
      def end_date
        T.must(context)[:end_date]&.to_s
      end
    end
  end
end
