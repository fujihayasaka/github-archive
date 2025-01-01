# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class ExportDataQuery < Export::DataQuery

      class RepositoryRowResult < T::Struct
        const :name_with_display_owner, String
        const :owner_type, T.nilable(String)
        const :archived, T::Boolean
        const :updated_at, String
        const :visibility, T.nilable(String)
        const :dependabot_alerts_count, T.nilable(Integer)
        const :code_scanning_alerts_count, T.nilable(Integer)
        const :secret_scanning_alerts_count, T.nilable(Integer)
        const :topics, T::Array[String]
        const :teams, T::Array[String]
      end

      sig { returns(User) }; attr_reader :user
      sig { returns(T.nilable(UserSession)) }; attr_reader :user_session
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope
      sig { returns(::Orgs::SecurityCenter::RiskController::RiskQueryParser) }; attr_reader :parser
      sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs
      sig { returns(T.nilable(T::Hash[Symbol, T::Array[Integer]])) }; attr_reader :allowed_repository_ids_by_feature

      class Result < T::Struct
        const :data, T::Array[RepositoryRowResult]
        const :total_pages, Integer
      end

      sig do
        params(
          user: User,
          scope: T.any(Organization, Business),
          parser: ::Orgs::SecurityCenter::RiskController::RiskQueryParser,
          authorized_orgs: T::Array[Organization],
          allowed_repository_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]]),
          user_session: T.nilable(UserSession)
        )
        .void
      end
      def initialize(user:, scope:, parser:, authorized_orgs: [], allowed_repository_ids_by_feature: nil, user_session: nil)
        @user = user
        @scope = scope
        @parser = parser
        @authorized_orgs = authorized_orgs
        @allowed_repository_ids_by_feature = allowed_repository_ids_by_feature
        @user_session = user_session

        @parser = @parser.class.new(@parser.add_or_replace(:sort, "repos"))
      end

      sig { params(page: T.nilable(Integer)).returns(Result) }
      def query_data(page: nil)
        list_data_query = if scope.is_a?(Organization)
          ListDataQuery.for_organization(
            user:,
            user_session:,
            organization: T.cast(scope, Organization),
            page_size: PAGE_SIZE,
            parser:,
            repo_ids_by_feature: allowed_repository_ids_by_feature,
          )
        else
          ListDataQuery.for_organizations(
            user:,
            user_session:,
            business: T.cast(scope, Business),
            organizations: authorized_orgs,
            page_size: PAGE_SIZE,
            parser:,
          )
        end

        data = if page.nil?
          T.cast(run(list_data_query:), T::Array[RepositoryRowResult])
        else
          T.cast(run_for_single_page(list_data_query:, page:), T::Array[RepositoryRowResult])
        end

        Result.new(data:, total_pages: list_data_query.counts.total_pages)
      end

      sig do
        override
          .params(name_with_display_owner: String, list_item: T.untyped, topics: T::Array[String], teams: T::Array[String])
          .returns(SecurityCenter::Risk::ExportDataQuery::RepositoryRowResult)
      end
      def create_repo_row_result(name_with_display_owner, list_item, topics, teams)
        RepositoryRowResult.new(
          name_with_display_owner:,
          owner_type: list_item.owner.is_a?(Organization) ? "ORGANIZATION" : "USER",
          archived: list_item.repo_metadata.archived,
          updated_at: list_item.repo_metadata.updated_at&.utc.to_s,
          visibility: list_item.repo_metadata.visibility,
          dependabot_alerts_count: list_item.repo_alert_count_map[:dependabot_alerts]&.alert_count,
          code_scanning_alerts_count: list_item.repo_alert_count_map[:code_scanning]&.alert_count,
          secret_scanning_alerts_count: list_item.repo_alert_count_map[:secret_scanning]&.alert_count,
          topics:,
          teams:,
        )
      end
    end
  end
end
