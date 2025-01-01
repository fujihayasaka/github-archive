# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  class AuthorizationEnumerator
    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper
    include Scientist

    DEFAULT_MEMCACHE_TTL_IN_SECONDS = 5

    sig { params(user: User, org: Organization, datadog_tags: T::Array[String]).void }
    def initialize(user:, org:, datadog_tags: [])
      @user = user
      @org = org
      @datadog_tags = datadog_tags
    end

    sig { returns(Integer) }
    def self.repo_limit_for_org_members
      3000
    end

    sig { returns(T.nilable(T::Hash[Symbol, T::Array[Integer]])) }
    def allowed_repository_ids_by_feature
      limited_repo_ids, _ = allowed_repository_ids_for_organization_member

      # if the user can manage security products for the org, they can manage for all repos
      return nil if limited_repo_ids.nil?

      allowed_repository_ids_by_feature_for_organization_member
        .reduce({}) do |memo, repo_ids_by_feature|
          feature_type = repo_ids_by_feature[0]
          repo_ids = repo_ids_by_feature[1][0]

          memo[feature_type] = (repo_ids & limited_repo_ids)
          memo
        end
        .with_indifferent_access
    end

    sig { returns([T.nilable(T::Array[Integer]), T::Boolean]) }
    memoize def allowed_repository_ids_for_organization_member
      # if the user can manage security products for the org, they can manage for all repos
      return [nil, false] if can_view_all_alerts?

      repo_ids_from_features, repo_limit_exceeded_from_features = allowed_repository_ids_by_feature_for_organization_member
        .reduce(T.let([[], false], [T::Array[Integer], T::Boolean])) do |memo, (_, (repo_ids, repo_limit_exceeded))|
          memo[0] |= repo_ids
          memo[1] |= repo_limit_exceeded
          memo
        end

      GitHub.dogstats.distribution(
        "security_center.get_repos_for_user.repo_count",
        repo_ids_from_features.length,
        tags: @datadog_tags + ["repo_limit_exceeded:#{repo_limit_exceeded_from_features}"]
      )

      [repo_ids_from_features, repo_limit_exceeded_from_features]
    end

    sig { returns([T.nilable(T::Array[Integer]), T::Boolean]) }
    memoize def adminable_repo_ids
      # If the user can manage security products for the org, they can manage for all repos
      return [nil, false] if can_manage_security_products?

      GitHub.dogstats.distribution_time "security_center.coverage.allowed_repo_ids.duration", tags: @datadog_tags do
        # Suppressing the linter and not providing a repository IDs filter here because
        # we provide an org and would just be passing in the results of
        # 'this_organization.repository_security_center_configs.pluck(:repository_id)' anyway.
        authorized_repo_ids = @user.associated_repository_ids(min_action: :admin, organization: @org) # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded

        exceeded_repo_limit = authorized_repo_ids.size >= self.class.repo_limit_for_org_members

        if exceeded_repo_limit
          GitHub.logger.warn(
            "Org member repo limit exceeded: #{authorized_repo_ids.size} repos",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "enduser.id": @user.display_login,
            "gh.enduser.id": @user.id,
            "gh.org.id": @org.id,
            "gh.org.login": @org.display_login,
          )

          authorized_repo_ids = \
            Repository.where(owner: @org) # `org.repositories` adds a default scope of `active=1`, which hurts index selection
              .where(id: authorized_repo_ids)
              # Order all repos based on last push:
              # - Use id as secondary sort is necessary to make sure consistent order when pushed_at are the same
              # - Use descending sort on ids to ensure we perform an index sort instead of sorting with a temp table
              .order(pushed_at: :desc, id: :desc)
              .limit(self.class.repo_limit_for_org_members + 1) # One more to check whether we actually hit the limit
              .pluck(:id)

          exceeded_repo_limit = authorized_repo_ids.size > self.class.repo_limit_for_org_members
          authorized_repo_ids = authorized_repo_ids.take(self.class.repo_limit_for_org_members) if exceeded_repo_limit
        end

        GitHub.dogstats.distribution(
          "security_center.get_repos_for_user.repo_count",
          authorized_repo_ids.length,
          tags: @datadog_tags + ["repo_limit_exceeded:#{exceeded_repo_limit}"]
        )

        [authorized_repo_ids, exceeded_repo_limit]
      end
    end

    sig { returns(T::Hash[String, [T::Array[Integer], T::Boolean]]) }
    memoize def allowed_repository_ids_by_feature_for_organization_member
      start_time = GitHub::Dogstats.monotonic_time
      cache_hit = T.let(true, T::Boolean)

      result = GitHub.cache.fetch(
        allowed_repository_ids_by_feature_for_organization_member_cache_key,
        ttl: allowed_repository_ids_by_feature_for_organization_member_cache_ttl.seconds
      ) do
        cache_hit = false
        allowed_repository_ids_by_feature_for_organization_member_implementation
      end

      GitHub.dogstats.distribution(
        "security_center.allowed_repository_ids_by_feature_for_organization_members.duration",
        GitHub::Dogstats.duration(start_time),
        tags: @datadog_tags + ["cache_hit:#{cache_hit}"]
      )

      result
    end

    private

    sig { returns(String) }
    memoize def allowed_repository_ids_by_feature_for_organization_member_cache_key
      # Example: "security_center/authorization_enumerator:allowed_repository_ids_by_feature_for_organization_member:12345:12345"
      "#{T.must(self.class.name).underscore}:allowed_repository_ids_by_feature_for_organization_member:#{@org.id}:#{@user.id}"
    end

    sig { returns(Integer) }
    memoize def allowed_repository_ids_by_feature_for_organization_member_cache_ttl
      factor_flag = "security_center_auth_enumerator_allowed_repository_ids_by_feature_for_organization_member_cache_factor".to_sym
      # percentage_of_actors_value ranges from 0.01 to 100
      factor_value = GitHub.flipper[factor_flag].percentage_of_actors_value
      factor_value = 1 if factor_value == 0
      (DEFAULT_MEMCACHE_TTL_IN_SECONDS * factor_value).round
    end

    sig { returns(T::Hash[String, [T::Array[Integer], T::Boolean]]) }
    memoize def allowed_repository_ids_by_feature_for_organization_member_implementation
      repo_limit = self.class.repo_limit_for_org_members

      args = T.let({ user: @user, actions: [], options: {} }, { user: User, actions: T::Array[Symbol], options: T::Hash[Symbol, T.untyped] })
      args[:actions] = visible_features.map do |feature_type|
        SecurityCenter::SecurityFeatures::VIEW_PERMISSIONS_BY_FEATURE_TYPE[feature_type]
      end.compact

      # No need to filter to user-visible here, as that's the point of the AuthorizationEnumerator.
      candidate_repo_ids = @org.repository_ids

      args[:options] = {
        organization: @org,
        repository_ids: candidate_repo_ids,
        include_oauth_restriction: false,
        include_indirect_forks: false,
        include_oopfs: false,
      }

      auth_enumerator = SecurityProduct::AuthorizationEnumerator.new(**args)

      repo_ids_by_permission = auth_enumerator.authorized_repository_ids_by_action

      repo_ids_by_feature_type = args[:actions].reduce({}) do |memo, view_permission|
        feature_type = SecurityCenter::SecurityFeatures::FEATURE_TYPES_BY_VIEW_PERMISSION[view_permission]
        memo[feature_type] = repo_ids_by_permission[view_permission] || []
        memo
      end

      org_repos = if repo_ids_by_feature_type.values.select { |authorized_repos| authorized_repos.size > repo_limit }.any?
        GitHub.dogstats.distribution_time "security_center.allowed_repository_ids_by_feature_for_organization_members.order_by_last_push.duration", tags: @datadog_tags do
          Repository.where(owner: @org) # `org.repositories` adds a default scope of `active=1`, which hurts index selection
            # Order all repos based on last push:
            # - Use id as secondary sort is necessary to make sure consistent order when pushed_at are the same
            # - Use descending sort on ids to ensure we perform an index sort instead of sorting with a temp table
            .order(pushed_at: :desc, id: :desc)
            .pluck(:id)
        end
      end

      repo_ids_by_feature_type.reduce({}) do |memo, (feature_type, authorized_repo_ids)|
        repo_ids, repo_limit_exceeded = if authorized_repo_ids.size > repo_limit
          # intersect the ordered result with the previously fetched authorized repo ids
          repo_ids = org_repos.intersection(authorized_repo_ids).take(repo_limit + 1)
          [repo_ids, repo_ids.length > repo_limit]
        else
          [authorized_repo_ids, false]
        end

        GitHub.dogstats.distribution(
          "security_center.allowed_repository_ids_by_feature_for_organization_members.repo_count",
          authorized_repo_ids.length,
          tags: @datadog_tags + [
            "repo_limit_exceeded:#{repo_limit_exceeded}",
            "feature_type:#{feature_type}"
          ]
        )

        if repo_limit_exceeded
          GitHub.logger.warn(
            "Org member repo limit exceeded: #{authorized_repo_ids.size} repos",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "enduser.id": @user.display_login,
            "gh.enduser.id": @user.id,
            "gh.org.id": @org.id,
            "gh.org.login": @org.display_login,
            "gh.security_center.feature_type": feature_type,
          )
        end

        memo[feature_type] = [repo_ids.take(repo_limit), repo_limit_exceeded]
        memo
      end.then do |reduced_repo_ids_by_feature|
        # We've collected the first 'repo_limit' repos for each feature type, but we need to make sure
        # for each repo we've collected that we include all the feature types that the user has authorization for.
        # For example, if our repo limit is 2, and the user has authorization for:
        #   - [1, 2, 3] for secret scanning
        #   - [2, 3, 4] for code scanning
        # we want to make sure we return [1, 2, 3] for secret scanning, not [1, 2]. This is because we are going to
        # return [2, 3] for code scanning, and we don't want to suggest the user only has authorization for code scanning for repo 3.
        all_authorized_repo_ids = reduced_repo_ids_by_feature.values.map(&:first).flatten.uniq
        reduced_repo_ids_by_feature.reduce({}) do |memo, (feature_type, (_, repo_limit_exceeded))|
          feature_authorized_repo_ids = repo_ids_by_feature_type[feature_type]
          repo_ids = feature_authorized_repo_ids.intersection(all_authorized_repo_ids)
          memo.tap { |m| m[feature_type] = [repo_ids, repo_limit_exceeded] }
        end
      end
    end

    sig { returns(T::Array[String]) }
    memoize def visible_features
      SecurityCenter::SecurityFeatures.visible_features(@org)
    end

    sig { returns(T::Boolean) }
    memoize def can_manage_security_products?
      SecurityProduct::Permissions::OrgAuthz.new(@org, actor: @user).can_manage_security_products?
    end

    sig { returns(T::Boolean) }
    memoize def can_view_all_alerts?
      org_authz = SecurityProduct::Permissions::OrgAuthz.new(@org, actor: @user)
      org_authz.can_view_all_alerts?
    end

    instrument_method \
      :adminable_repo_ids,
      :allowed_repository_ids_by_feature,
      :allowed_repository_ids_by_feature_for_organization_member,
      :allowed_repository_ids_for_organization_member
  end
end
