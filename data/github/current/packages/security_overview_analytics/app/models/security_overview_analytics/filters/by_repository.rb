# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByRepository
      extend T::Sig
      include Filter

      sig do
        params(
          incl_filters: T::Array[String],
          excl_filters: T::Array[String],
          substring_match: T::Boolean,
          scope: T.nilable(T.any(Organization, Business))
        ).void
      end
      def initialize(incl_filters, excl_filters, substring_match: false, scope: nil)
        @incl_filters = incl_filters
        @excl_filters = excl_filters
        @substring_match = substring_match
        @scope = scope
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        if @incl_filters.present?
          rel = if @substring_match
            if @scope.is_a?(Business)
              nwo_substring_match(rel, @incl_filters)
            else
              rel.with_substrings(:name, @incl_filters)
            end
          else
            where(rel, @incl_filters)
          end
        end

        if @excl_filters.present?
          rel = if @substring_match
            if @scope.is_a?(Business)
              nwo_substring_match(rel, @excl_filters, neg: true)
            else
              rel.without_substrings(:name, @excl_filters)
            end
          else
            where(rel, @excl_filters, neg: true)
          end
        end

        rel
      end

      sig { override.returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      sig { override.returns(T::Boolean) }
      def has_incl_filters?
        @incl_filters.present?
      end

      private

      sig { params(rel: ActiveRecord::Relation, filters: T::Array[String], neg: T::Boolean).returns(ActiveRecord::Relation) }
      def where(rel, filters, neg: false)
        repo_names, repo_names_by_owner = parse_repo_names(filters)

        # Standalone repo names
        repo_rel = rel.where(name: repo_names) unless neg
        repo_rel = rel.where.not(name: repo_names) if neg

        return repo_rel unless repo_names_by_owner.any?

        # Repo names with owner slugs
        nwo_rel = neg ? ::SecurityOverviewAnalytics::Repository.all : ::SecurityOverviewAnalytics::Repository.none
        repo_names_by_owner.map do |owner_slug, repo_names|
          owner_id = User.where(login: owner_slug).pluck(:id).first
          if @scope.is_a?(Business)
            rel_conditions = { owner_id:, name: repo_names }
          else
            rel_conditions = { organization_id: owner_id, name: repo_names }
          end

          nwo_rel = nwo_rel.or(::SecurityOverviewAnalytics::Repository.where(rel_conditions)) unless neg
          nwo_rel = nwo_rel.and(::SecurityOverviewAnalytics::Repository.where.not(rel_conditions)) if neg
        end

        return rel.and(repo_rel.or(nwo_rel)) unless neg
        return rel.and(repo_rel).and(nwo_rel) if neg
      end

      sig { params(rel: ActiveRecord::Relation, filters: T::Array[String], neg: T::Boolean).returns(ActiveRecord::Relation) }
      def nwo_substring_match(rel, filters, neg: false)
        raise "NWO substring matching is only supported at the Business scope" unless @scope.is_a?(::Business)

        standalone_names, repo_names_by_owner = parse_repo_names(filters)
        standalone_rel = neg ? rel : ::SecurityOverviewAnalytics::Repository.none
        nwo_rel = neg ? rel : ::SecurityOverviewAnalytics::Repository.none

        if standalone_names.present?
          # substring match on repos, orgs, or usernames
          if neg
            repo_rel = rel.without_substrings(:name, standalone_names)
          else
            repo_rel = rel.with_substrings(:name, standalone_names)
          end

          org_ids = nwo_org_substring_rel(standalone_names, neg)
          user_ids = nwo_user_substring_rel(standalone_names, neg)
          owner_ids = org_ids | user_ids

          standalone_rel = repo_rel

          # If the submatch matched against any orgs/users, include into the query
          if owner_ids.any?
            owner_rel = rel.where(owner_id: owner_ids)
            standalone_rel = standalone_rel.or(owner_rel) unless neg
            standalone_rel = standalone_rel.and(owner_rel) if neg
          end
        end

        return rel.and(standalone_rel) unless repo_names_by_owner.any?

        repo_names_by_owner.map do |owner_slug, repo_names|
          # Fetch any matching users
          user_rel = ::SecurityOverviewAnalytics::Repository.none
          user_id = if GitHub.enterprise?
            User.where(type: "User", login: owner_slug).pluck(:id).first
          else
            @scope.user_accounts.where(login: owner_slug).pluck(:user_id).first
          end

          # Fetch any matching orgs
          org_id = @scope.organizations.where(display_login: owner_slug).pluck(:id)
          owner_id = org_id | user_id

          if neg
            owner_rel = rel.where.not(owner_id: owner_id)
            repo_rel = rel.without_substrings(:name, repo_names)
            nwo_rel = T.cast(nwo_rel.and(repo_rel.or(owner_rel)), ActiveRecord::Relation)
          else
            owner_rel = rel.where(owner_id: owner_id)
            repo_rel = rel.with_substrings(:name, repo_names)
            nwo_rel = nwo_rel.or((repo_rel).and(owner_rel))
          end
        end

        return rel.and((standalone_rel).or(nwo_rel)) unless neg
        return rel.and(standalone_rel).and(nwo_rel) if neg
      end

      sig { params(names: T::Array[String], negate: T::Boolean).returns(T::Array[String]) }
      def nwo_org_substring_rel(names, negate)
        raise "NWO substring matching is only supported at the Business scope" unless @scope.is_a?(::Business)

        if negate
          @scope.organizations.without_substrings("display_login", names).pluck(:id)
        else
          @scope.organizations.with_substrings("display_login", names).pluck(:id)
        end
      end

      sig { params(names: T::Array[String], negate: T::Boolean).returns(T::Array[String]) }
      def nwo_user_substring_rel(names, negate)
        raise "NWO substring matching is only supported at the Business scope" unless @scope.is_a?(::Business)

        rel = if GitHub.enterprise?
          User.where(type: "User").not_suspended
        else
          return ::SecurityOverviewAnalytics::Repository.none.pluck(:id) unless @scope.enterprise_managed? && @scope.external_provider.present?
          # Note that this uses the `BusinessUserAccount table`
          # We could use `ExternalIdentity` which is more specific for EMU accounts, but it doesn't
          # contain information around their GitHub username (i.e. "<foo>_<slug>") for us to
          # filter further by.
          @scope.user_accounts
        end
        col = GitHub.enterprise? ? :display_login : :login
        id_col = GitHub.enterprise? ? :id : :user_id

        if negate
          rel.without_substrings(col, names).pluck(id_col)
        else
          rel.with_substrings(col, names).pluck(id_col)
        end
      end

      # parse_repo_names takes in a list of filters that represent substrings
      # of repository NWOs. i.e. "some_user", "some_use", "some_user/foo", "foo"
      # The function returns two lists,
      # 1. An array of entries that do not look like NWOs
      # 2. An array of entries that look like NWOs, grouped by the owner
      # For example, given the input ["user_a/repo-", "user_b", "foo"]
      # This method would return:
      # [
      #   ["user_b", "foo"],
      #   {"user_a" => ["repo-"]},
      # ]
      sig { params(filters: T::Array[String]).returns([T::Array[String], T::Hash[String, T::Array[String]]]) }
      def parse_repo_names(filters)
        repo_nwos, repo_names = filters.partition { |name| name.include?("/") }
        repo_names_by_owner = repo_names_by_owner(repo_nwos)

        [repo_names, repo_names_by_owner]
      end

      sig { params(repo_nwos: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
      def repo_names_by_owner(repo_nwos)
        Hash.new { |h, k| h[k] = [] }.tap do |org_to_repo_names|
          repo_nwos.each do |repo_nwo|
            org_slug, repo_name = T.cast(repo_nwo.split("/", 2), [String, String])
            org_to_repo_names[org_slug.downcase] << repo_name
          end
        end
      end
    end
  end
end
