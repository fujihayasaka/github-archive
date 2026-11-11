# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class SubjectStats < StatsBase
    extend T::Helpers
    include RateLimitedSummaryFilterable
    include Sortable
    include Pageable

    sig { params(organization_id: Integer, min_timestamp: Time, max_timestamp: Time).void }
    def initialize(organization_id, min_timestamp, max_timestamp)
      super organization_id, min_timestamp, max_timestamp

      query.summary_key_fields << Queries::SummaryKeyField::SubjectType
      query.summary_key_fields << Queries::SummaryKeyField::SubjectId
      query.summary_key_fields << Queries::SummaryKeyField::SubjectName
      query.summary_key_fields << Queries::SummaryKeyField::IntegrationIdWhenSubjectInstallation
    end

    sig { params(value: SubjectType).returns(T.self_type) }
    def with_subject_type(value)
      query.filters << Queries::Filter.new(Queries::FilterField::SubjectType, value.serialize)
      self
    end

    sig { params(subject_name_substring: String).returns(T.self_type) }
    def with_subject_name_substring(subject_name_substring)
      query.filters << Queries::Filter.new(Queries::FilterField::SubjectName, subject_name_substring, operator: "contains")
      self
    end

    private

    sig { override.params(sort_field: Queries::SortField).returns(T::Boolean) }
    def valid_sort_field?(sort_field)
      return true if super sort_field

      sort_field == Queries::SortField::SubjectName
    end
  end
end
