# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class DependabotAlertsAclFilter < ::Search::Filters::TermFilter
      # This filter works by setting either an `owner_id` (org id) or `repository_id` field and a list of values that the current user is authorized to view.
      #
      # 1. Repo scope - The `repository_id` field gets set to the value of that repo.
      # 2. Org scope - We prefer to use the fewest number of filter values possible
      #   - If the user has access to see all vulnerability alerts in the org, either as an admin or with the appropriate PAT or FGP token,
      #     we return a filter on `owner_id: [org.id]` rather than `repo_id: [potentially long list of repo ids]`
      #       - This avoids issues with ES query field length limits when orgs have many repos
      #       - This sidesteps a perf issue we observed where Authz took a long time to enumerate all the accessible repo ids in large orgs
      #   - If the user can only access a subset of repos in the org, we return a filter of `repo_id: [potentially long list of repo ids]`
      # 3. Business scope - when querying for alerts in a business we only check for alerts at the org level.  So we'll send over a filter like `owner_id: [list of accessible org ids]` for the user

      class Error < StandardError; end
      ORG_FIELD = :owner_id
      REPO_FIELD = :repository_id

      MISSING_CAP_FILTER_ERROR = Error.new(<<~ERR.squish)
        A Conditional Access Policy (CAP) filter is required when querying business scope but was not provided.
        Please provide the :cap_filter option when initializing this filter.
      ERR

      sig { returns(Symbol) }
      attr_reader :field

      sig { returns(T::Array[Integer]) }
      attr_reader :values

      sig { returns(T.nilable(Symbol)) }
      attr_reader :org_field

      sig { returns(T.nilable(Symbol)) }
      attr_reader :repo_field

      # Scope can be a Repository, Organization, or Business
      # Sorbet has limitations with flow-sensitive typing on method calls, so that's why it's untyped.
      # sig { returns(T.any(Repository, Organization, Business)) }
      sig { returns(T.untyped) }
      attr_reader :scope

      sig { returns(User) }
      attr_reader :current_user

      sig { returns(T.nilable(ConditionalAccess::Filter)) }
      attr_reader :cap_filter

      sig { params(opts: T::Hash[T.untyped, T.untyped]).void }
      def initialize(opts = {})
        super(opts)
        @scope = opts.fetch(:scope)
        @current_user = opts.fetch(:current_user)
        @cap_filter = opts.fetch(:cap_filter, nil)

        bool_collection
      end

      sig { returns(Search::ParsedQuery::BoolCollection) }
      def bool_collection
        return @bool_collection if defined? @bool_collection

        @field, @values = field_and_values
        if @values.blank?
          @values = [::Search::Filter::MISSING]
        end

        @bool_collection = ::Search::ParsedQuery::BoolCollection.new @field
        @bool_collection.must @values

        @bool_collection
      end

      sig { returns([Symbol, T::Array[Integer]]) }
      def field_and_values
        if @scope.is_a?(Business)
          business_scoped_acl
        elsif @scope.is_a?(Organization)
          organization_scoped_acl
        else
          # We rely on the prior Alert access checks in the UI/API code paths for performance.
          [REPO_FIELD, [scope.id]]
        end
      end

      sig { returns([Symbol, T::Array[Integer]]) }
      def business_scoped_acl
        raise MISSING_CAP_FILTER_ERROR if cap_filter.nil?

        fgp = :view_dependabot_alerts
        values = T.must(
          ::SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor: current_user,
            business: scope,
            actions: fgp,
            cap_filter: T.must(cap_filter),
          ).authorized_orgs_by_action[fgp]
        ).map(&:id)

        [ORG_FIELD, values]
      end

      sig { returns([Symbol, T::Array[Integer]]) }
      def organization_scoped_acl
        if programmatic_actor_grant = ProgrammaticActor::Grant.with(current_user).with_target(scope)
          programmatic_actor_acl(programmatic_actor_grant)
        elsif current_user.oauth_access.present?
          oauth_access_acl
        elsif SecurityProduct::Permissions::OrgAuthz.new(scope, actor: current_user).can_view_all_alerts?
          [ORG_FIELD, [scope.id]]
        else
          values, _ = org_auth_enumerator.allowed_repository_ids_by_feature_for_organization_member[SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]
          [REPO_FIELD, values || []]
        end
      end

      # If the request is made with a programmatic actor (i.e: PAT v2, or GitHub Apps) and the actor cannot access all
      # repos in the org, we find only the repos that the actor can access.
      # When the request is made with an OAuth app or a legacy PAT, and `security_events` is not part of the scope, we find only public repos of the org.
      # Otherwise, we set `repository_ids` to `nil`, which means that the actor can access all repos in the org.
      sig { params(programmatic_actor_grant: T.untyped).returns([Symbol, T::Array[Integer]]) }
      def programmatic_actor_acl(programmatic_actor_grant)
        if programmatic_actor_grant.installed_on_all_repositories?
          [ORG_FIELD, [scope.id]]
        else
          repo_ids = programmatic_actor_grant.repository_ids(min_action: :read, resource: "vulnerability_alerts")
          if repo_ids.empty?
            raise Error, "The programmatic actor does not have access to any repositories in the organization"
          end

          [REPO_FIELD, repo_ids]
        end
      end

      # If the request is made with an OAuth app or a legacy PAT, check the request scopes
      # to determine what repositories the user should have access to - security_events gives
      # access to all repos, otherwise only public repos are accessible.
      sig { returns([Symbol, T::Array[Integer]]) }
      def oauth_access_acl
        if Api::AccessControl.scope?(current_user, "security_events")
          [ORG_FIELD, [scope.id]]
        else
          repo_ids = scope.public_repositories.pluck(:id)
          if repo_ids.empty?
            raise Error, "The OAuth app does not have access to any public repositories in the organization"
          end

          [REPO_FIELD, repo_ids]
        end
      end

      sig { returns(SecurityCenter::AuthorizationEnumerator) }
      def org_auth_enumerator
        SecurityCenter::AuthorizationEnumerator.new(user: current_user, org: scope)
      end
    end
  end
end
