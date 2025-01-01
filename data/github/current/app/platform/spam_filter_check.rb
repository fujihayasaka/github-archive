# typed: true
# frozen_string_literal: true
module Platform
  # This is added in development & test
  # to make sure that all ActiveRecord::Relatations
  # that _can_ be filtered to remove spam
  # _are_ filtered to remove spam.
  module SpamFilterCheck
    module ResolveWrapper
      def resolve(obj, args, ctx)
        # Call the usual resolve function
        result = super
        # Maybe a Promise or a GraphQL::Execution::Lazy from authorization
        ctx.schema.after_lazy(result) do |items|
          SpamFilterCheck.check_result(self, items, ctx)
        end
      end
    end

    class << self
      def check_result(field, result, ctx)
        if !GitHub.spamminess_check_enabled? || !result.is_a?(ActiveRecord::Relation)
          # This can't possibly be spammy because either:
          # - spam checking is disabled OR
          # - it's not a relation
          result
        elsif field.exempt_from_spam_filter_check
          # Skip this, it's been opted-out
          result
        else
          # It might be spammy, so let's make sure it's filtered
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
              # We don't expect to filter spam for site admins,
              # so don't check for a filter in the SQL.
              result
            elsif unfiltered_spam?(result)
              # If the result _could_ have been filtered, but it wasn't filtered,
              # raise an error in development
              raise Platform::Errors::UnfilteredSpam.new(result, field_name: field.name, owner_type_name: field.owner.name)
            else
              # Otherwise, just return it.
              # We can't make any assertions about its spam-filtering status.
              result
            end
          end
        end
      end

      private

      # These conditions are added by `Spammable.filter_spam_for`, `User.filter_spam_for` or `Spammy.not_spammy`
      SPAM_FILTER_CLAUSES = [
        "user_hidden = false",
        "`user_hidden` = false",
        "user_hidden = 0",
        "`user_hidden` = 0",
        "spammy = false",
        "`spammy` = false",
        "spammy = 0",
        "`spammy` = 0",
        # Some empty relations are implemented this way:
        "WHERE 1=0",
      ]
      private_constant :SPAM_FILTER_CLAUSES

      # Is this relation leaking spam?
      # Returns Boolean
      def unfiltered_spam?(relation)
        if relation.null_relation?
          # This is a `.none` relation
          false
        elsif relation.klass < Spam::Spammable || relation.klass <= User
          # Check the relation for SQL that filters out spam
          sql_query = relation.to_sql
          SPAM_FILTER_CLAUSES.none? { |clause| sql_query.include?(clause) }
        else
          # It doesn't seem like this relation _can_ filter out spam,
          # so don't apply any checks.
          false
        end
      end
    end
  end
end
