# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The RepositoryFilter is critical for ensuring that users only see the
    # private repository data that they are allowed to see. Any documents in
    # the search index that contain private data have two fields associated
    # with them: a `public` field and a `repo_id` field.
    #
    # Anyone is allowed to see documents where `public` is true. For
    # everything else, the user needs to have permission to see the document.
    # This is determined by performing database queries and then returning a
    # list of private repository IDs the user is allowed to see. This list is
    # used as a terms filter against the `repo_id` field.
    class RepositoryFilter < ::Search::Filter
      include GitHub::Memoizer
      include Scientist

      # Maximum size of the generated private repository filter. TODO: Apply limits to other repo filters as well.
      MAX_REPO_FILTER_SIZE = 4_000
      MAX_CONSIDERED_REPOSITORY_IDS = 10_000

      # Increased limits to address missing results for unqualified searches
      INCREASED_MAX_REPO_FILTER_SIZE = 20_000
      INCREASED_MAX_CONSIDERED_REPOSITORY_IDS = 20_000

      # The set of qualifiers that restrict the scope of the repository filter. This should be kept in sync with
      # the qualifiers used in `must_repository_ids`.
      SCOPED_QUALIFIERS = %i[user repo org owner contributed-by adminable-by].freeze

      attr_reader :current_user, :user_session, :ip

      attr_reader :repo_id

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :limit_to_repo_ids

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :candidate_private_repo_ids

      # Create a new RepositoryFilter.
      #
      # opts - The options Hash
      #   :current_user - the currently logged in User
      #   :cap_filter   - Filter object to check permissions, if available
      #                   This is an alternative to passing user_session & ip to create a cap_filter inside.
      #   :repo_id      - restrict the filter to a single repository
      #   :resource     - restrict the filter to repositories where the user has
      #                   access to the specified resource
      #   :candidate_private_repo_ids - an Array of repository IDs to use for searching
      #   :allow_finder_filters - Allow the `contributed-by:` and `adminable-by:` filters to be used.
      #
      def initialize(opts = {})
        super(opts)

        allowed_resources = Repository::Resources.subject_types
        options.delete(:resource) unless allowed_resources.include?(options[:resource])

        @field ||= :repo_id
        @keys = nil
        @single_repo = nil

        @repo_id      = options.fetch(:repo_id, nil)
        @cap_filter   = options.fetch(:cap_filter, nil)
        @current_user = options.fetch(:current_user, nil)
        @user_session = options.fetch(:user_session, nil)
        @resource     = options.fetch(:resource, "contents")
        @ip           = options.fetch(:ip, nil)
        @candidate_private_repo_ids = options.fetch(:candidate_private_repo_ids, nil)
        @limit_to_repo_ids = options.fetch(:limit_to_repo_ids, nil)
        @allow_finder_filters = options.fetch(:allow_finder_filters, false)

        bool_collection  # initialize our boolean collection
      end

      # This reason can be used when the repository filter is invalid.
      def invalid_reason
        "The listed users and repositories cannot be searched either because the resources do not exist or you do not have permission to view them."
      end

      # Returns `true` if the generated filter includes all public
      # repositories.
      def global?
        !bool_collection.must?
      end

      # Returns `true` if the limit MAX_REPO_FILTER_SIZE was applied
      def hit_max_repo_filter_limit?
        @hit_max_repo_filter_limit ||= false
      end

      # Public: the number of repo IDs in this filter
      def repo_ids_size
        return bool_collection.must.size if bool_collection.must?
        return bool_collection.should.size if bool_collection.should?
        0
      end

      # Returns nil or a filter Hash.
      def must
        if bool_collection.must?
          build_term_filter(field, bool_collection.must)

        elsif bool_collection.should?
          { bool: {
            should: [
              { term: { public: true } },
              build_term_filter(field, bool_collection.should),
            ].compact,
          } }
        else
          { term: { public: true } }
        end
      end

      # Returns nil or a filter Hash.
      def must_not
        build_term_filter(field, bool_collection.must_not)
      end

      # A `should` filter is not applicable to the repository filter.
      #
      # Returns nil
      def should; end

      # This filter will never be blank.
      #
      # Returns false
      def blank?
        false
      end

      # Override the superclass method and make it into a noop.
      #
      # Returns nil
      def build(values); end

      # Validates whether the given repo is accessible by current user,
      # checking also the cap filter for the business authorization
      def accessible_repository?(repo)
        return true if repo.public?

        @include_repos ||= accessible_repository_ids
        return true if @include_repos.include?(repo.id)

        true if accessible_business_ids.include?(repo.internal_visibility_business_id)
      end

      # For validating search results, this filter provides the set of all
      # accessible repository IDs that were allowed by the search criteria.
      # Results can be validated against this set of repository IDs.
      #
      # Returns a Set containing the accessible repository IDs.
      sig { returns(Set) }
      def accessible_repository_ids
        set = Set.new(bool_collection.must)
        set.merge(bool_collection.should) if bool_collection.should?
        set
      end

      memoize def accessible_business_ids
        return [] unless current_user
        # when removing idp_cap_for_web_enabled?, we can remove the extra check for is_enterprise_managed?, it was added here
        # to just see if the configurable was enabled on the business
        if current_user.is_enterprise_managed? && current_user.enterprise_managed_business&.idp_cap_for_web_enabled?
          cap_filter.authorized_resource_ids(current_user.businesses, exclude: [:ip_allowlist, :external_conditional_access_policy])
        else
          cap_filter.authorized_resource_ids(current_user.businesses, exclude: [:ip_allowlist])
        end
      end

      def enterprise_filter_enabled?
        GitHub.enterprise_repo_search_filter_enabled?
      end

      def include_repos_from_unqualified_orgs?
        [
          enterprise_filter_enabled?,
          qualifiers[:org].blank?,
          qualifiers[:owner].blank?,
          qualifiers[:repo].blank?,
          current_user.present?
        ].all?
      end

      def private_repos_permitted?
        return false if qualifiers[:is].must? && qualifiers[:is].must.include?("public")
        can_search_private_repositories_for_user?
      end

      def apply_recently_updated_sort(scope)
        scope.order(Arel.sql(
          "repositories.parent_id IS NULL DESC," \
          "GREATEST(repositories.updated_at, repositories.pushed_at) DESC," \
          "repositories.id",
        ))
      end

      # Internal: Create the boolean collection that will be used by the
      # repository filter. The :repo and :user/:org/:owner keys from the
      # qualifiers hash are used to construct this collection. If there are no
      # :repo or :user/:org/:owner entries, then we try to include the current
      # user's private repository IDs.
      #
      # If current_user has access to too many private repositories to
      # efficiently use as a query filter, the list will be truncated, favoring
      # sources over forks and then ordering by a proxy for repo activity.
      #
      # Returns this filter's boolean collection.
      sig { returns(Search::ParsedQuery::BoolCollection) }
      memoize def bool_collection
        bool_collection = ::Search::ParsedQuery::BoolCollection.new

        # If limit_to_repo_ids is an empty array, no repositories can match.
        if !limit_to_repo_ids.nil? && limit_to_repo_ids.blank?
          @valid = false
          return bool_collection
        end

        if repo_id.nil?
          @repo_id = include_single_repo_via_org_membership
        end

        unless repo_id.nil?
          bool_collection.must repo_id
          return bool_collection
        end

        bool_collection.must(must_repository_ids)
        bool_collection.must_not(must_not_repository_ids)
        bool_collection.should(should_repository_ids)

        # Validate there is at least one repository ID in the boolean collection when exclusive qualifiers are used
        # or if there are any `must` repository IDs.
        if scoped_qualifiers?
          ids = bool_collection.must&.uniq || []

          bool_collection.must = filter_repository_ids(ids)
          @valid &&= bool_collection.must?
        elsif (repo_ids = limit_to_repo_ids)
          # For global searches with limit_to_repo_ids, restrict to only those repositories.
          # This is used for semantic search to limit results to the user's top repositories.
          # Note: should_repository_ids already applies limit_to_repo_ids via filter_repository_ids.
          bool_collection.must(filter_repository_ids(repo_ids))
        end

        # prune `must_not` repository IDs from the `must` and `should` lists
        bool_collection.intersect!

        GitHub.dogstats.histogram("search.query.repository_filter.must", bool_collection.must.size) if bool_collection.must?
        GitHub.dogstats.histogram("search.query.repository_filter.should", bool_collection.should.size) if bool_collection.should?
        GitHub.dogstats.histogram("search.query.repository_filter.must_not", bool_collection.must_not.size) if bool_collection.must_not?

        bool_collection
      end

      # Internal: Override the superclass method and make it a noop
      # implementation. Mapping the boolean collection is not applicable for
      # the repository filter.
      #
      # Returns this filter's boolean collection.
      def map_bool_collection
        bool_collection
      end

      # Internal: if user is a member of an enterprise org we return a union of all the repos associated with the users AND all the internal repos
      # If a user has no internal repos, an empty array is returned from `internal_repo_ids`
      def readable_repository_ids(repository_ids:, resource:)
        (current_user.associated_repository_ids(repository_ids: repository_ids, resource: resource) + current_user.internal_repo_ids).uniq.sort
      end

      # Internal: Return all the repository IDs from the `repo` qualifier using
      # name_with_owner values, that the `current_user` is allowed to access.
      #
      # repo_nwos - Full user/repo String or an Array of Strings
      #
      # Returns an Array of repository IDs.
      def repository_ids_from_repo(repo_nwos)
        return [] if repo_nwos.nil?

        repos = Array(repo_nwos)
          .map { |name_with_owner| Repository.nwo(name_with_owner) }
          .reject(&:nil?)

        public_repos, private_repos = repos.partition(&:public?)
        public_repo_ids = public_repos.map(&:id)

        unless can_search_private_repositories_for_user? && private_repos.any?
          return filter_repository_ids(public_repo_ids)
        end

        repo_ids_readable_by_user = readable_repository_ids(
          repository_ids: private_repos.map(&:id),
          resource: @resource
        )

        readable_by_user = private_repos.select do |repo|
          repo_ids_readable_by_user.include?(repo.id)
        end

        accessible_private_repos =
          if current_user.using_auth_via_granular_actor?
            readable_by_user.select do |repo|
              ability_delegate = current_user.programmatic_ability_delegate_for_repository(repo)
              repo.resources.public_send(@resource).readable_by?(ability_delegate)
            end
          else
            GitHub::PrefillAssociations.prefill_associations(
              readable_by_user, :organization
            )

            readable_by_user.select do |repo|
              Api::AccessControl.oauth_application_policy_satisfied?(current_user, repo)
            end
          end

        filter_repository_ids(public_repo_ids.concat(accessible_private_repos.map(&:id)))
      end

      # Internal: Return all the repository IDs that belong to the `users` that
      # the `current_user` is allowed to access.
      #
      # users - User login as a String or an Array of Strings
      # limit_to_repo_ids - an Array of repository IDs to limit the results to
      # ids_already_searchable - a boolean to indicate that the passed values are already ids accessible to the user
      #
      # Returns an Array of Repository IDs.
      def repository_ids_from_user(users, limit_to_repo_ids: nil, ids_already_searchable: false)
        ids = []
        return ids if users.blank?

        user_ids = ids_already_searchable ? users : searchable_user_ids(Array(users))

        ids.concat Repository.where(active: true, public: true, owner_id: user_ids).pluck(:id)

        if can_search_private_repositories_for_user?

          if accessible_business_ids.any?
            ids.concat Repository.active.where(owner_id: user_ids).joins(
              :internal_repository).where("internal_repositories.business_id IN (?)",
              accessible_business_ids).pluck(:id)
          end

          private_repository_ids = T.let([], T::Array[Integer])
          GH.context.act_as(current_user) do
            private_repository_ids = ::Repositories.domain.private_repo_ids_by_owner_for_actor(owner_id: user_ids, resource: @resource)
          end

          granted_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
            actor: current_user,
            repository_ids: private_repository_ids,
            resource: @resource,
          )

          ids.concat(private_repository_ids & granted_repository_ids)
        end

        ids = ids.compact.uniq
        limit_to_repo_ids.present? ? ids & limit_to_repo_ids : ids
      end

      def contributed_repo_ids_from_user(users)
        return [] unless current_user
        return [] unless @allow_finder_filters
        return [] unless Array(users).include?("@me")

        contributed_repos = current_user.repositories_contributed_to(
          viewer: current_user,
          limit: nil,
          exclude_owned: false,
          since: 1.year.ago,
        )

        public_repos, private_repos = contributed_repos.partition(&:public?)

        ids = public_repos.map(&:id)

        if can_search_private_repositories_for_user?
          ids += current_user.associated_repository_ids(
            min_action: :read,
            resource: @resource,
            repository_ids: private_repos.map(&:id),
          )
        end

        filter_repository_ids(ids)
      end

      def adminable_repo_ids_from_user(users)
        return [] unless current_user
        return [] unless @allow_finder_filters
        return [] unless Array(users).include?("@me")

        filter_repository_ids(current_user.associated_repository_ids(min_action: :admin)) # rubocop:disable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      end

      def searchable_user_ids(logins)
        users = User.where(login: logins, spammy: false)

        if FeatureFlag.vexi.enabled_or_raise?(:invalidate_private_profile_searches, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          users = users.with_visible_profiles_for(current_user)
        end

        users.pluck(:id)
      end

      # Private: Return a smaller set of repository_ids if the search space
      # would be too large. Note: This set is sorted to increase the chance
      # of hits for users with access to many repositories.
      #
      # Also only consider the first MAX_CONSIDERED_REPOSITORY_IDS repository
      # IDs if the collection is too large
      def limit_repository_ids(repository_ids)
        considered_repository_ids = MAX_CONSIDERED_REPOSITORY_IDS
        repo_filter_ids_size = MAX_REPO_FILTER_SIZE
        limit_stats = "search.query.repository_filter.hit_max_repo_filter_limit"

        if ::FeatureFlag.vexi.enabled?(:issues_search_increased_repo_limits, @current_user, default: false)
          # The considered number must be larger than the repo filter size otherwise we will never trip the
          # hit_max_repo_filter_limit condition below. That condition checks if the repo filter size was exceeded and
          # it can't be exceeded if we only consider exactly the number we allow in the filter.
          considered_repository_ids = INCREASED_MAX_CONSIDERED_REPOSITORY_IDS + 1
          repo_filter_ids_size = INCREASED_MAX_REPO_FILTER_SIZE
          limit_stats = "search.query.repository_filter.hit_increased_max_repo_filter_limit"
        end

        scope = Repository.private_scope.where(id: repository_ids.first(considered_repository_ids))
        ids = apply_recently_updated_sort(scope).limit(repo_filter_ids_size + 1).ids

        @hit_max_repo_filter_limit = ids.size > repo_filter_ids_size
        GitHub.dogstats.increment(limit_stats) if @hit_max_repo_filter_limit

        ids.take(repo_filter_ids_size)
      end

      # Internal: Determine whether private repositories can be included in the
      # query. Private repositories can only be included if we have a currently-
      # logged-in user. If we're performing the query for an OAuth request,
      # then we also need 'repo' scope in order to search the user's accessible
      # private repositories.
      #
      # Returns true if the list of accessible repositories should be determined
      #   based on the permissions of +current_user+. Returns false if only
      #   public repositories are accessible.
      def can_search_private_repositories_for_user?
        return false unless current_user
        Api::AccessControl.scope?(current_user, "repo")
      end

      # Private: The account logins to exclude from results based on
      # whether the current user does not meet any of the conditional access policies
      # (e.g. SAML policy or IP allow list policy)
      #
      # Returns Array of String.
      private def protected_account_logins
        cap_filter.unauthorized_resources(
          current_user&.resources_for_cap_filter
        ).pluck(:login)
      end

      alias :remote_ip :ip

      # used by CAP framework through a callback
      def logged_in?
        !!current_user
      end

      def cap_filter
        @cap_filter ||= ConditionalAccess::Web::Filter.new(self) # rubocop:disable GitHub/DoNotInstantiatePlatformObjects
      end

      # Private: List of repo ids to exclude from results based on
      # conditional access policies.
      def protected_repo_ids
        @protected_repo_ids ||= repository_ids_from_user(protected_account_logins)
      end
      private :protected_repo_ids

      def include_single_repo_via_org_membership
        return nil unless @repo_id.blank?
        return nil unless single_repo_filter?

        if @single_repo.nil?
          load_single_repo(qualifiers[:repo].must.first)
        end

        if @single_repo.present? && valid_current_user? &&
          !unauthorized_org_logins.include?(@single_repo.owner_display_login) &&
          @single_repo.visible_and_readable_by?(current_user)

          # For non-public repositories, verify OAuth token has repo scope
          if !@single_repo.public? && !can_search_private_repositories_for_user?
            return nil
          end

          return @single_repo.id
        end

        nil
      end
      private :include_single_repo_via_org_membership

      def single_repo_filter?
        if !qualifiers[:repo].blank? && qualifiers.filter { |k, _| %i[user org owner].include?(k) }.all? { |_, v| v.blank? }
          qr = qualifiers[:repo]
          return !qr.must.blank? && qr.must.uniq.size == 1 && qr.must_not.blank? && qr.should.blank?
        end
        false
      end
      private :single_repo_filter?

      def load_single_repo(nwo)
        owner, name = nwo.split("/")
        @single_repo ||= T.unsafe(Repository.preload(:organization)).nwo(owner, name)
      end
      private :load_single_repo

      def unauthorized_org_logins
        return [] unless @single_repo.present?
        return @unauthorized_org_logins if defined?(@unauthorized_org_logins)

        resources = current_user&.resources_for_cap_filter&.to_a
        resources = if resources.present?
          resources << @single_repo.organization if @single_repo.organization.present?
          resources
        else
          @single_repo.organization
        end

        @unauthorized_org_logins = cap_filter.unauthorized_resources(resources).pluck(:display_login).uniq
      end
      private :unauthorized_org_logins

      def valid_current_user?
        current_user && !current_user.using_auth_via_granular_actor?
      end
      private :valid_current_user?

      private

      # Filter out protected repository IDs from the given list of repository IDs. Also apply
      # the `limit_to_repo_ids` restriction if it is set.
      sig { params(repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def filter_repository_ids(repository_ids)
        filtered_ids = repository_ids - protected_repo_ids
        return filtered_ids unless (limit_to_repo_ids = self.limit_to_repo_ids)

        filtered_ids & limit_to_repo_ids
      end

      # Determine whether any of the scoped qualifiers are present in the search query.
      sig { returns(T::Boolean) }
      def scoped_qualifiers?
        SCOPED_QUALIFIERS.any? do |key|
          if (key == :"contributed-by" || key == :"adminable-by") && !@allow_finder_filters
            next false
          end

          # user:hubot or user:hubot,monalisa
          qualifiers[key].must? || qualifiers[key].and_should?
        end
      end

      # Internal: Return the list of repository IDs from the qualifiers to be used in the
      # boolean collection.
      #
      # It also marks the query as invalid if any of the qualifiers result in no repositories.
      sig { returns(T::Array[Integer]) }
      memoize def must_repository_ids
        repository_ids = []

        repo_qualifiers = [
          qualifiers[:repo].must, # q=repo:foo
          qualifiers[:repo].and_should, # q=repo:github/github,github/mobile
        ].flatten.compact
        if repo_qualifiers.any?
          repository_ids.concat(repository_ids_from_repo(repo_qualifiers))
        end

        user_qualifiers = [
          qualifiers[:user].must, # q=user:foo
          qualifiers[:user].and_should, # q=user:foo,bar
          qualifiers[:org].must, # q=org:organization
          qualifiers[:org].and_should, # q=org:org1,org2
          qualifiers[:owner].must, # q=owner:organization
          qualifiers[:owner].and_should, # q=owner:org1,org2
        ].flatten.compact
        if user_qualifiers.any?
          repository_ids.concat(repository_ids_from_user(user_qualifiers, limit_to_repo_ids:))
        end

        if @allow_finder_filters
          if (users = qualifiers[:"contributed-by"].must) && users.any?
            ids = contributed_repo_ids_from_user(users)
            @valid &&= ids.any?
            return repository_ids unless @valid

            # Take existing repositories and narrow it down to those also contributed to by the user
            repository_ids = intersect_ids(repository_ids, ids)
          end

          if (users = qualifiers[:"adminable-by"].must) && users.any?
            ids = adminable_repo_ids_from_user(users)
            @valid &&= ids.any?
            return repository_ids unless @valid

            # Take existing repositories and narrow it down to those also adminable by the user
            repository_ids = intersect_ids(repository_ids, ids)
          end
        end

        filter_repository_ids(repository_ids.uniq)
      end

      sig { returns(T::Array[Integer]) }
      memoize def must_not_repository_ids
        repository_ids = repository_ids_from_repo(qualifiers[:repo].must_not) # q=-repo:foo/bar

        user_qualifiers = [
          qualifiers[:user].must_not, # q=-user:foo
          qualifiers[:org].must_not, # q=-org:organization
          qualifiers[:owner].must_not, # q=-owner:organization
        ].flatten.compact
        if user_qualifiers.any?
          repository_ids.concat(repository_ids_from_user(user_qualifiers))
        end

        if @allow_finder_filters
          repository_ids.concat(contributed_repo_ids_from_user(qualifiers[:"contributed-by"].must_not)) # q=-contributed-by:@me
          repository_ids.concat(adminable_repo_ids_from_user(qualifiers[:"adminable-by"].must_not)) # q=-adminable-by:@me
        end

        repository_ids.uniq
      end

      # Include the user's accessible private and internal repositories if private searches are permitted and none of
      # the other qualifiers introduced mutually exclusive constraints.
      sig { returns(T::Array[Integer]) }
      memoize def should_repository_ids
        repository_ids = []
        qualifiers_added_constraints = scoped_qualifiers? && must_repository_ids.any?
        return repository_ids unless private_repos_permitted? && !qualifiers_added_constraints

        if include_repos_from_unqualified_orgs?
          repository_ids += repository_ids_from_user(
            Organization.pluck(:id), ids_already_searchable: true
          )
        end

        # NOTE: repository_ids here includes both public and private repos that are _directly_ accessible to the
        # current user, but then `limit_repository_ids` we filter out the public ones. If would be nice to teach
        # `associated_repository_ids` to only retrieve private repos.
        repository_ids += current_user.associated_repository_ids(
          min_action: :read,
          resource: @resource,
          repository_ids: candidate_private_repo_ids,
        )

        # Any internal repos that are behind SAML-protected orgs will get filtered out below
        # when `protected_repo_ids` are removed from `@bool_collection.should`.
        if accessible_business_ids.any?
          repository_ids.concat(::Repositories.domain.internal_repo_ids_by_business_ids(business_ids: accessible_business_ids, active_only: true))
        end

        # If we are using a granular actor, limit the repository ids for the search space
        if current_user.using_auth_via_granular_actor?
          repository_ids = ProgrammaticActor::RepositoryFilter.perform(
            actor: current_user,
            repository_ids: repository_ids,
            resource: @resource,
          )
        end

        # remove any repo ids that do not meet conditional access policies
        repository_ids = filter_repository_ids(repository_ids)

        # remove repos explicitly excluded - this might seem redundant because it happens again when calling
        # `intersect!` on the BoolCollection but we need to remove every unnecessary thing we can before the
        # truncation that happens in `limit_repository_ids`
        repository_ids -= must_not_repository_ids

        # Get a (possibly-truncated) list of ids to filter on
        repository_ids = if include_repos_from_unqualified_orgs?
          scope = Repository.where(id: repository_ids)
          apply_recently_updated_sort(scope).pluck(:id)
        else
          limit_repository_ids(repository_ids)
        end

        repository_ids.uniq
      end

      def intersect_ids(a, b)
        return a if b.blank?
        return b if a.blank?
        a & b
      end
    end  # RepositoryFilter
  end  # Filters
end  # Search
