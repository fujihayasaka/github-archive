# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class RequestorHasActivity
    extend T::Helpers

    sig { returns(T::Array[ApiInsights::Stats::Queries::BaseFilter]) }
    attr_reader :filters

    sig { returns(T::Array[ApiInsights::Stats::Queries::SummaryKeyField]) }
    attr_reader :project_by

    sig { returns(String) }
    attr_reader :tabular_input

    sig { params(organization_id: Integer).void }
    def initialize(organization_id)
      max_timestamp = Time.now
      min_timestamp = max_timestamp - 31.days

      @filters = T.let([], T::Array[ApiInsights::Stats::Queries::BaseFilter])
      @filters << Queries::Filter.new(Queries::FilterField::OrganizationId, organization_id)
      @filters << Queries::RangeFilter.new(Queries::FilterField::Timestamp, min_timestamp, max_timestamp)
      @tabular_input = T.let(GitHub.api_insights_active_kusto_tabular_input, String)

      @project_by = T.let([], T::Array[ApiInsights::Stats::Queries::SummaryKeyField])
    end

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    def get
      # It's important to avoid any mysql queries in this method to avoid threading errors.
      # Note that this includes any feature flag checks.
      dataset = KustoClientProvider.kusto_client.query(GitHub.api_insights_kusto_database_name, query_text, parameters)
      result = dataset.primary_result_table.rows.map do |row|
        dataset.primary_result_table.columns.each_with_index.each_with_object({}) do |(column, i), hash|
          hash[column.name] = row[i] unless row[i].nil?
        end
      end
      result.first
    end

    sig { returns(String) }
    def query_text
      raise Error.new(ErrorCode::FILTERS_NOT_SPECIFIED) if @filters.empty?
      raise Error.new(ErrorCode::SUMMARY_FIELDS_NOT_SPECIFIED) if @project_by.empty?
      missing_tenant_id = GitHub.multi_tenant_enterprise? && !@filters.any? { |f| f.field == Queries::FilterField::TenantId }
      raise "Current tenant is not set and is required in multi-tenant mode" if missing_tenant_id

      value = String.new
      value << <<~KQL
        #{@tabular_input}
        | where
        #{@filters.map { |c| "    #{c}" }.join(" and\n")}
        | take 1
        | project
        #{@project_by.map { |a| "    #{a}" }.join(",\n")}
        KQL
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def parameters
      merged_parameters = T.let({}, T::Hash[String, T.untyped])
      merged_parameters = merged_parameters.merge(@filters.map(&:parameters).reduce({}, &:merge))
      merged_parameters
    end

    sig { params(tenant_id: Integer).void }
    def with_tenant_id(tenant_id)
      @filters << Queries::Filter.new(Queries::FilterField::TenantId, tenant_id)
    end

    sig { params(user_id: Integer).returns(T.self_type) }
    def with_user(user_id)
      @filters << Queries::Filter.new(Queries::FilterField::SubjectId, user_id)
      @filters << Queries::Filter.new(Queries::FilterField::SubjectType, SubjectType::User.serialize)

      @project_by << Queries::SummaryKeyField::SubjectId
      @project_by << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_oauth_app(access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::OauthApp.serialize)

      @project_by << Queries::SummaryKeyField::ActorId
      @project_by << Queries::SummaryKeyField::ActorName
      @project_by << Queries::SummaryKeyField::SubjectId
      @project_by << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_classic_pat(access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::ClassicPat.serialize)

      @project_by << Queries::SummaryKeyField::ActorId
      @project_by << Queries::SummaryKeyField::ActorName
      @project_by << Queries::SummaryKeyField::SubjectId
      @project_by << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_fine_grained_pat(access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::FineGrainedPat.serialize)

      @project_by << Queries::SummaryKeyField::ActorId
      @project_by << Queries::SummaryKeyField::ActorName
      @project_by << Queries::SummaryKeyField::SubjectId
      @project_by << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_github_app_user_to_server(access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::GithubAppUserToServer.serialize)

      @project_by << Queries::SummaryKeyField::ActorId
      @project_by << Queries::SummaryKeyField::ActorName
      @project_by << Queries::SummaryKeyField::SubjectId
      @project_by << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(installation_id: Integer).returns(T.self_type) }
    def with_installation(installation_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorId, installation_id)
      @filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::Installation.serialize)

      @project_by << Queries::SummaryKeyField::ActorId
      @project_by << Queries::SummaryKeyField::ActorName
      self
    end
  end
end
