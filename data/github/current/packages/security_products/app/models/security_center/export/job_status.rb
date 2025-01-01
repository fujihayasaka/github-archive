# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Export
    class JobStatus < ::JobStatus
      extend T::Sig
      include ::JobStatus::Context

      PREFIX = "security-center-export"

      sig { params(id: String, query: String, requested_at: T.nilable(Time), start_date: T.nilable(::Date), end_date: T.nilable(::Date), kwargs: T.untyped).returns(JobStatus) }
      def self.create(id:, query:, requested_at:, start_date: nil, end_date: nil, **kwargs)
        raise ArgumentError, "Providing a context is not supported" if kwargs.key?(:context)

        requested_at ||= Time.now
        context = { query:, requested_at: requested_at.dup.utc, start_date:, end_date: }

        super(ttl: 10.minutes, **kwargs, id: "#{PREFIX}-#{id}", context:)
      end

      sig { override.params(ttl: ActiveSupport::Duration).void }
      def success!(ttl: DEFAULT_COMPLETED_JOB_TTL)
        super(ttl: 3.days)
      end

      sig { params(id: String).returns(T.nilable(JobStatus)) }
      def self.find(id)
        super("#{PREFIX}-#{id}")
      end

      sig { returns(String) }
      def query
        T.must(context)[:query]
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
