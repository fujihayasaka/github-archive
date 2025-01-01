# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class RequestorFilterableTest < GitHub::TestCase
    setup do
      @requestor_filterable = FakeRequestorFilterable.new
    end

    test "adds user filters" do
      @requestor_filterable.with_user(1)
      filters = @requestor_filterable.query.filters

      assert filters.any? { |filter| filter.field == Queries::FilterField::SubjectId && filter.value == 1 }
      assert filters.any? { |filter| filter.field == Queries::FilterField::SubjectType && filter.value == SubjectType::User.serialize }

      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectName
    end

    test "adds oauth app filters" do
      @requestor_filterable.with_oauth_app(1)
      filters = @requestor_filterable.query.filters

      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorId && filter.value == 1 }
      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorType && filter.value == ActorType::OauthApp.serialize }

      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorName
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectName
    end

    test "adds classic pat filters" do
      @requestor_filterable.with_classic_pat(1)
      filters = @requestor_filterable.query.filters

      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorId && filter.value == 1 }
      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorType && filter.value == ActorType::ClassicPat.serialize }

      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorName
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectName
    end

    test "adds fine grained pat filters" do
      @requestor_filterable.with_fine_grained_pat(1)
      filters = @requestor_filterable.query.filters

      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorId && filter.value == 1 }
      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorType && filter.value == ActorType::FineGrainedPat.serialize }

      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorName
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectName
    end

    test "adds github app user to server filters" do
      @requestor_filterable.with_github_app_user_to_server(1)
      filters = @requestor_filterable.query.filters

      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorId && filter.value == 1 }
      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorType && filter.value == ActorType::GithubAppUserToServer.serialize }

      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorName
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::SubjectName
    end

    test "adds installation filters" do
      @requestor_filterable.with_installation(1)
      filters = @requestor_filterable.query.filters

      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorId && filter.value == 1 }
      assert filters.any? { |filter| filter.field == Queries::FilterField::ActorType && filter.value == ActorType::Installation.serialize }

      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorId
      assert_includes @requestor_filterable.query.summary_key_fields, Queries::SummaryKeyField::ActorName
    end
  end

  class FakeRequestorFilterable < StatsBase
    include RequestorFilterable

    def initialize
      now = Time.now.utc
      super 1, now - 1.day, now
    end

    def query
      super
    end
  end
end
