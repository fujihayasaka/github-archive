# typed: true
# frozen_string_literal: true
module Platform
  # This is added in development & test
  # to make sure that all ActiveRecord::Relations for repositories
  # that _can_ be filtered to remove disabled (DMCA'd etc) repositories
  # _are_ filtered to remove them.
  module DisabledRepositoryFilterCheck
    module ResolveWrapper
      def resolve(obj, args, ctx)
        # Call the usual resolve function
        result = super
        # Maybe a Promise or a GraphQL::Execution::Lazy from authorization
        ctx.schema.after_lazy(result) do |items|
          DisabledRepositoryFilterCheck.check_result(self, items, ctx)
        end
      end
    end

    class << self
      def check_result(field, result, ctx)
        if !result.is_a?(ActiveRecord::Relation)
          # We can't check to see if we are filtering disabled repositories if it's not a relation
          result
        else
          # It might have disabled repositories that need to be filtered, so check if they are
          viewer = ctx[:viewer]
          async_is_site_admin = if viewer
            viewer.async_two_factor_credential.then do |_cred|
              viewer.site_admin?
            end
          else
            Promise.resolve(false)
          end

          async_is_site_admin.then do |is_site_admin|
            if is_site_admin
              # We don't expect to filter disabled repositories for site admins,
              # so don't check for a filter in the SQL.
              result
            elsif unfiltered_disabled_repos?(result)
              # If the result _could_ have been filtered, but it wasn't filtered,
              # raise an error in development
              raise Platform::Errors::UnfilteredDisabledRepositories.new(field, result, ctx)
            else
              # Otherwise, just return it.
              # We can't make any assertions about its spam-filtering status.
              result
            end
          end
        end
      end

      private

      # These conditions are added by `Repository.filter_spam_and_disabled_for`
      DISABLED_REPOSITORY_FILTER_CLAUSES = [
        "disabled_at IS NULL",
        "`disabled_at` IS NULL",
        # Some empty relations are implemented this way:
        "WHERE 1=0",
        "WHERE (false)",
      ]
      private_constant :DISABLED_REPOSITORY_FILTER_CLAUSES

      # Is this relation leaking disabled repos?
      # Returns Boolean
      def unfiltered_disabled_repos?(relation)
        if relation.null_relation?
          # This is a `.none` relation
          false
        elsif relation.klass == Repository
          # Check the relation for SQL that filters out spam
          sql_query = relation.to_sql
          DISABLED_REPOSITORY_FILTER_CLAUSES.none? { |clause| sql_query.include?(clause) }
        else
          # No need to filter disabled repositories if it's not a repository association
          false
        end
      end
    end
  end
end
