# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  module AsyncDependency

    sig { returns(T.nilable(Integer)) }
    def tenant_id
      # It is important to calls this in the current request thread so tenant_id is available, not the future thread
      tenant_id = GitHub::CurrentTenant.get.id if GitHub.multi_tenant_enterprise?
    end

    sig do
      params(
        organization_id: Integer,
        user_id: T.nilable(Integer),
        actor_id: T.nilable(Integer),
        actor_type: T.nilable(::ApiInsights::Stats::ActorType),
        installation_id: T.nilable(Integer),
      ).returns(Concurrent::Promises::Future)
    end
    def async_requestor_has_activity(organization_id:, user_id: nil, actor_id: nil, actor_type: nil, installation_id: nil)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::RequestorHasActivity.new(organization_id)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_user(user_id) if user_id
        q.with_installation(installation_id) if installation_id
        q.with_oauth_app(actor_id) if actor_id && actor_type == ::ApiInsights::Stats::ActorType::OauthApp
        q.with_classic_pat(actor_id) if actor_id && actor_type == ::ApiInsights::Stats::ActorType::ClassicPat
        q.with_fine_grained_pat(actor_id) if actor_id && actor_type == ::ApiInsights::Stats::ActorType::FineGrainedPat
        q.with_github_app_user_to_server(actor_id) if actor_id && actor_type == ::ApiInsights::Stats::ActorType::GithubAppUserToServer
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_requestor_has_activity", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig { params(min: Time, max: Time, organization_id: Integer).returns(Concurrent::Promises::Future) }
    def async_summary_stats(min:, max:, organization_id:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::SummaryStats.new(organization_id, min, max)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_summary_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do params(
        min: Time,
        max: Time,
        organization_id: Integer,
        installation_id: Integer
      ).returns(Concurrent::Promises::Future)
    end
    def async_installation_summary_stats(min:, max:, organization_id:, installation_id:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::SummaryStats.new(organization_id, min, max)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_installation(installation_id)
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_installation_summary_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig { params(min: Time, max: Time, organization_id: Integer, user_id: Integer).returns(Concurrent::Promises::Future) }
    def async_user_summary_stats(min:, max:, organization_id:, user_id:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::SummaryStats.new(organization_id, min, max)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_user(user_id)
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_user_summary_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do params(
      min: Time,
      max: Time,
      organization_id: Integer,
      actor_id: Integer,
      actor_type: T.nilable(::ApiInsights::Stats::ActorType)
    ).returns(
      Concurrent::Promises::Future
    )
    end
    def async_actor_summary_stats(min:, max:, organization_id:, actor_id:, actor_type:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::SummaryStats.new(organization_id, min, max)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_oauth_app(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::OauthApp
        q.with_classic_pat(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::ClassicPat
        q.with_fine_grained_pat(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::FineGrainedPat
        q.with_github_app_user_to_server(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::GithubAppUserToServer
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_actor_summary_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do params(
      organization_id: Integer,
      min: Time,
      max: Time,
      timestamp_increment: String
    ).returns(Concurrent::Promises::Future)
    end
    def async_summary_time_stats(organization_id:, min:, max:, timestamp_increment:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::TimeStats.new(organization_id, min, max, timestamp_increment)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_summary_time_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do params(
      organization_id: Integer,
      min: Time,
      max: Time,
      timestamp_increment: String,
      installation_id: Integer
    ).returns(Concurrent::Promises::Future)
    end
    def async_installation_time_stats(organization_id:, min:, max:, timestamp_increment:, installation_id:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::TimeStats.new(organization_id, min, max, timestamp_increment)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_installation(installation_id)
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_installation_time_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do params(
      organization_id: Integer,
      min: Time,
      max: Time,
      timestamp_increment: String,
      user_id: Integer
    ).returns(Concurrent::Promises::Future)
    end
    def async_user_time_stats(organization_id:, min:, max:, timestamp_increment:, user_id:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::TimeStats.new(organization_id, min, max, timestamp_increment)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_user(user_id)
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_user_time_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do
      params(
        organization_id: Integer,
        min: Time,
        max: Time,
        timestamp_increment: String,
        actor_id: Integer,
        actor_type: T.nilable(::ApiInsights::Stats::ActorType)
      ).returns(Concurrent::Promises::Future)
    end
    def async_actor_time_stats(organization_id:, min:, max:, timestamp_increment:, actor_id:, actor_type:)
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::TimeStats.new(organization_id, min, max, timestamp_increment)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_oauth_app(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::OauthApp
        q.with_classic_pat(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::ClassicPat
        q.with_fine_grained_pat(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::FineGrainedPat
        q.with_github_app_user_to_server(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::GithubAppUserToServer
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_actor_time_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do
      params(
        organization_id: Integer,
        min: Time,
        max: Time,
        sorts: T::Array[::ApiInsights::Stats::Queries::SortDefinition],
        page: Integer,
        per_page: Integer,
        rate_limited_summaries: T::Boolean,
        subject_type: T.nilable(::ApiInsights::Stats::SubjectType),
        name_substring: T.nilable(String)
      ).returns(Concurrent::Promises::Future)
    end
    def async_summary_subject_stats(
      organization_id:,
      min:,
      max:,
      sorts:,
      page:,
      per_page:,
      rate_limited_summaries: false,
      subject_type: nil,
      name_substring: nil
    )
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::SubjectStats.new(organization_id, min, max)
        .with_sorting(sorts)
        .with_paging(page: page, per_page: per_page)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_rate_limited_summaries(true) if rate_limited_summaries
        q.with_subject_type(subject_type) if subject_type
        q.with_subject_name_substring(name_substring) if name_substring
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_summary_subject_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do
      params(
        organization_id: Integer,
        min: Time,
        max: Time,
        installation_id: Integer,
        page: Integer,
        per_page: Integer,
        sorts: T::Array[::ApiInsights::Stats::Queries::SortDefinition],
        route_substring: T.nilable(String)
      ).returns(Concurrent::Promises::Future)
    end
    def async_route_installation_stats(organization_id:, min:, max:, installation_id:, page:, per_page:, sorts:, route_substring: nil)
      tid = tenant_id
      begin
        q = ApiInsights::Stats::RouteStats.new(organization_id, min, max)
          .with_installation(installation_id)
          .with_sorting(sorts)
          .with_paging(page:, per_page:)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_api_route_substring(route_substring) if route_substring
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_route_installation_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do
      params(
        organization_id: Integer,
        min: Time,
        max: Time,
        page: Integer,
        per_page: Integer,
        sorts: T::Array[::ApiInsights::Stats::Queries::SortDefinition],
        actor_id: Integer,
        actor_type: T.nilable(::ApiInsights::Stats::ActorType),
        route_substring: T.nilable(String)
      ).returns(Concurrent::Promises::Future)
    end
    def async_actor_route_installation_stats(organization_id:, min:, max:, page:, per_page:, sorts:, actor_id:, actor_type:, route_substring: nil)
      tid = tenant_id
      begin
        q = ApiInsights::Stats::RouteStats.new(organization_id, min, max)
          .with_sorting(sorts)
          .with_paging(page:, per_page:)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_oauth_app(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::OauthApp
        q.with_classic_pat(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::ClassicPat
        q.with_fine_grained_pat(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::FineGrainedPat
        q.with_github_app_user_to_server(actor_id) if actor_type == ::ApiInsights::Stats::ActorType::GithubAppUserToServer
        q.with_api_route_substring(route_substring) if route_substring
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_actor_route_installation_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end

    sig do
      params(
        organization_id: Integer,
        user_id: Integer,
        min: Time,
        max: Time,
        sorts: T::Array[::ApiInsights::Stats::Queries::SortDefinition],
        page: Integer,
        per_page: Integer,
        rate_limited_summaries: T::Boolean,
        name_substring: T.nilable(String),
        type: T.nilable(ActorType)
      ).returns(Concurrent::Promises::Future)
    end
    def async_user_stats(
      organization_id:,
      user_id:,
      min:,
      max:,
      sorts:,
      page:,
      per_page:,
      rate_limited_summaries: false,
      name_substring: nil,
      type: nil
    )
      tid = tenant_id
      begin
        q = ::ApiInsights::Stats::UserStats.new(organization_id, min, max, user_id)
          .with_sorting(sorts)
          .with_paging(page: page, per_page: per_page)
        q.with_tenant_id(tid) if GitHub.multi_tenant_enterprise? && tid
        q.with_actor_name_substring(name_substring) if name_substring
        q.with_actor_type(type) if type
        q.with_rate_limited_summaries(true) if rate_limited_summaries
        Concurrent::Promises.future do
          GitHub.tracer.in_span("ApiInsights::Stats::AsyncDependency#async_user_stats", kind: :internal) do |_span|
            q.get
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Concurrent::Promises.rejected_future(e)
      end
    end
  end
end
