# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class SortBy
      extend T::Sig
      include GitHub::Memoizer

      SORT_BY_LAST_UPDATED_REPO = T.let(:"last-updated", Symbol)
      SORT_BY_REPO_NAME = T.let(:repos, Symbol)
      SORT_BY_DEPENDABOT_ALERTS = T.let(:dependabot, Symbol)
      SORT_BY_CODE_SCANNING_ALERTS = T.let(:"code-scanning", Symbol)
      SORT_BY_SECRET_SCANNING_ALERTS = T.let(:"secret-scanning", Symbol)

      ALERTS_SORT_OPTIONS = T.let([
        SORT_BY_DEPENDABOT_ALERTS,
        SORT_BY_CODE_SCANNING_ALERTS,
        SORT_BY_SECRET_SCANNING_ALERTS
      ], T::Array[Symbol])
      ALL_SORT_OPTIONS = T.let([
        SORT_BY_LAST_UPDATED_REPO,
        SORT_BY_REPO_NAME,
        *ALERTS_SORT_OPTIONS
      ], T::Array[Symbol])
      DEFAULT_SORT_OPTION = SORT_BY_LAST_UPDATED_REPO

      sig { returns(Symbol) }; attr_reader :sort_option
      sig { returns(T::Array[Organization]) }; attr_reader :organizations
      sig { returns(Integer) }; attr_reader :page_size

      sig do
        params(
          sort_option: T.nilable(String),
          organizations: T::Array[Organization],
          page_size: Integer
        ).void
      end
      def initialize(sort_option, organizations:, page_size:)
        @sort_option = T.let(sort_option_or_default(sort_option), Symbol)
        @organizations = organizations
        @page_size = page_size
      end

      sig do
        params(
          rel: ActiveRecord::Relation,
          page: Integer
        ).returns(ActiveRecord::Relation)
      end
      def apply(rel, page:)
        return apply_sort_on_repository_properties(rel) unless sort_by_feature_alerts?
        apply_sort_on_feature_alerts(rel, page:)
      end

      private

      sig { params(sort_option: T.nilable(String)).returns(Symbol) }
      def sort_option_or_default(sort_option)
        sort_option = sort_option&.downcase&.to_sym
        ALL_SORT_OPTIONS.include?(sort_option) ? T.must(sort_option) : DEFAULT_SORT_OPTION
      end

      sig { returns(T::Boolean) }
      memoize def sort_by_feature_alerts?
        ALERTS_SORT_OPTIONS.include?(sort_option)
      end

      sig { returns(String) }
      memoize def default_configs_table_name
        RepositorySecurityCenterConfig.table_name
      end

      sig { returns(String) }
      memoize def default_statuses_table_name
        RepositorySecurityCenterStatus.table_name
      end

      sig { returns(Arel::Nodes::SqlLiteral) }
      memoize def default_sort
        Arel.sql("`#{default_configs_table_name}`.`last_push` DESC, `#{default_configs_table_name}`.`name` ASC")
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply_sort_on_repository_properties(rel)
        case sort_option
        when SORT_BY_REPO_NAME
          rel.order(Arel.sql("`#{default_configs_table_name}`.`name` ASC, `#{default_configs_table_name}`.`last_push` DESC"))
        when SORT_BY_LAST_UPDATED_REPO
          rel.order(Arel.sql("`#{default_configs_table_name}`.`last_push` DESC, `#{default_configs_table_name}`.`name` ASC"))
        else
          GitHub.logger.warn(
            "Unknown sort option. Use default sort instead.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_center.sort_option": sort_option
          )
          rel.order(default_sort)
        end
      end

      sig { params(filter: Symbol).returns(String) }
      def filter_to_feature_type(filter)
        return "dependabot_alerts" if filter == :dependabot
        sort_option.to_s.underscore
      end

      sig do
        params(
          rel: ActiveRecord::Relation,
          page: Integer
        ).returns(ActiveRecord::Relation)
      end
      def apply_sort_on_feature_alerts(rel, page:)
        data_size = page * page_size
        feature_type = filter_to_feature_type(sort_option)

        rel_with_feature_scope = rel
          .joins(:repository_security_center_statuses)
          .where(repository_security_center_statuses: {
            owner_id: organizations,
            feature_type: feature_type,
            scanning_status: "enrolled"
          })
          .where("`#{default_statuses_table_name}`.`scanning_count` > 0")
          .order(Arel.sql(
            "`#{default_statuses_table_name}`.`scanning_count` DESC, `#{default_configs_table_name}`.`last_push` DESC"
          ))
          .select("`#{default_configs_table_name}`.`id`")
          .limit(data_size)

        rel_without_feature_scope = rel
          .order(Arel.sql("`#{default_configs_table_name}`.`last_push` DESC"))
          .select("`#{default_configs_table_name}`.`id`")
          .limit(data_size)

        RepositorySecurityCenterConfig
          .joins(
            "LEFT JOIN `#{default_statuses_table_name}`" \
            " ON `#{default_statuses_table_name}`.`repository_id` = `#{default_configs_table_name}`.`repository_id`" \
            " AND `#{default_statuses_table_name}`.`feature_type` = '#{feature_type}'"
          )
          .joins("INNER JOIN ((#{rel_with_feature_scope.to_sql}) UNION (#{rel_without_feature_scope.to_sql})) AS `filtered_repos` ON `filtered_repos`.`id` = `#{default_configs_table_name}`.`id`")
          .order(Arel.sql("COALESCE(`#{default_statuses_table_name}`.`scanning_count`, 0) DESC, #{default_configs_table_name}.last_push DESC"))
      end
    end
  end
end
