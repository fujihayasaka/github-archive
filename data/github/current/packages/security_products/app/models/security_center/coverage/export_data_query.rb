# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class ExportDataQuery < Export::DataQuery

      class RepositoryRowResult < T::Struct
        const :name_with_display_owner, String
        const :owner_type, T.nilable(String)
        const :archived, T::Boolean
        const :updated_at, String
        const :visibility, String
        const :dependabot_alerts_status, T.nilable(String)
        const :dependabot_security_updates_status, T.nilable(String)
        const :code_scanning_alerts_status, T.nilable(String)
        const :code_scanning_pull_request_alerts_status, T.nilable(String)
        const :code_scanning_default_setup, T.nilable(String)
        const :secret_scanning_alerts_status, T.nilable(String)
        const :secret_scanning_push_protection_status, T.nilable(String)
        const :advanced_security_status, T.nilable(String)
        const :topics, T::Array[String]
        const :teams, T::Array[String]
      end

      class Result < T::Struct
        const :data, T::Array[RepositoryRowResult]
        const :total_pages, Integer
      end

      sig { returns(User) }; attr_reader :user
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope
      sig { returns(::Orgs::SecurityCenter::CoverageController::CoverageQueryParser) }; attr_reader :parser
      sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs
      sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repository_ids
      sig { returns(T.nilable(UserSession)) }; attr_reader :user_session

      sig do
        params(
          user: User,
          scope: T.any(Organization, Business),
          parser: ::Orgs::SecurityCenter::CoverageController::CoverageQueryParser,
          authorized_orgs: T::Array[Organization],
          allowed_repository_ids: T.nilable(T::Array[Integer]),
          user_session: T.nilable(UserSession)
        )
        .void
      end
      def initialize(user:, scope:, parser:, authorized_orgs: [], allowed_repository_ids: nil, user_session: nil)
        @user = user
        @scope = scope
        @parser = parser
        @authorized_orgs = authorized_orgs
        @allowed_repository_ids = allowed_repository_ids
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
            repo_ids: allowed_repository_ids,
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
        .returns(SecurityCenter::Coverage::ExportDataQuery::RepositoryRowResult)
      end
      def create_repo_row_result(name_with_display_owner, list_item, topics, teams)
        RepositoryRowResult.new(
          name_with_display_owner:,
          owner_type: list_item.owner.is_a?(Organization) ? "ORGANIZATION" : "USER",
          archived: list_item.repo_metadata.archived,
          updated_at: list_item.repo_metadata.updated_at&.utc.to_s,
          visibility: list_item.repo_metadata.visibility,
          advanced_security_status: list_item.repo_metadata.ghas_enabled ? "enabled" : "not-enabled",
          dependabot_alerts_status: feature_status(list_item.repo_coverages_list[0].feature_statuses[:dependabot_alerts]),
          dependabot_security_updates_status: feature_status(list_item.repo_coverages_list[0].feature_statuses[:dependabot_security_updates]),
          code_scanning_alerts_status: feature_status(list_item.repo_coverages_list[1].feature_statuses[:code_scanning]),
          code_scanning_pull_request_alerts_status: feature_status(list_item.repo_coverages_list[1].feature_statuses[:code_scanning_pr_reviews]),
          code_scanning_default_setup: feature_status(list_item.repo_coverages_list[1].feature_statuses[:code_scanning_auto_codeql]),
          secret_scanning_alerts_status: feature_status(list_item.repo_coverages_list[2].feature_statuses[:secret_scanning]),
          secret_scanning_push_protection_status: feature_status(list_item.repo_coverages_list[2].feature_statuses[:secret_scanning_push_protection]),
          topics:,
          teams:,
        )
      end

      sig { params(feature_status: T.nilable(String)).returns(T.nilable(String)) }
      def feature_status(feature_status)
        return if feature_status.nil?

        case feature_status
        when "enrolled"
          "enabled"
        when "not_eligible"
          "ineligible"
        else
          "not-enabled"
        end
      end
    end
  end
end
