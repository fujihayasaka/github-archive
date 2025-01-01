# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class SortBy
      extend T::Sig
      include GitHub::Memoizer

      SORT_BY_LAST_UPDATED_REPO = T.let(:"last-updated", Symbol)
      SORT_BY_REPO_NAME = T.let(:repos, Symbol)

      ALL_SORT_OPTIONS = T.let([
        SORT_BY_LAST_UPDATED_REPO,
        SORT_BY_REPO_NAME
      ], T::Array[Symbol])
      DEFAULT_SORT_OPTION = SORT_BY_LAST_UPDATED_REPO

      sig { returns(Symbol) }; attr_reader :sort_option

      sig { params(sort_option: T.nilable(String)).void }
      def initialize(sort_option)
        @sort_option = T.let(sort_option_or_default(sort_option), Symbol)
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
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

      private

      sig { params(sort_option: T.nilable(String)).returns(Symbol) }
      def sort_option_or_default(sort_option)
        sort_option = sort_option&.downcase&.to_sym
        ALL_SORT_OPTIONS.include?(sort_option) ? T.must(sort_option) : DEFAULT_SORT_OPTION
      end

      sig { returns(String) }
      memoize def default_configs_table_name
        RepositorySecurityCenterConfig.table_name
      end

      sig { returns(Arel::Nodes::SqlLiteral) }
      memoize def default_sort
        Arel.sql("`#{default_configs_table_name}`.`last_push` DESC, `#{default_configs_table_name}`.`name` ASC")
      end
    end
  end
end
