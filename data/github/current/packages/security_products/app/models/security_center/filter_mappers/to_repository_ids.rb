# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module FilterMappers
    class ToRepositoryIds
      extend T::Sig
      include GitHub::Memoizer

      class InputFilters < T::Struct
        const :name_substrings, [T::Array[String], T::Array[String]], default: [[], []]
        const :names, [T::Array[String], T::Array[String]], default: [[], []]
        const :visibilities, [T::Array[String], T::Array[String]], default: [[], []]
        const :archived, [T::Array[String], T::Array[String]], default: [[], []]
        const :topics, [T::Array[String], T::Array[String]], default: [[], []]
        const :teams, [T::Array[String], T::Array[String]], default: [[], []]
        const :code_scanning_alerts, [T::Array[String], T::Array[String]], default: [[], []]
        const :dependabot_alerts, [T::Array[String], T::Array[String]], default: [[], []]
        const :secret_scanning_alerts, [T::Array[String], T::Array[String]], default: [[], []]
        const :custom_properties, String, default: ""
      end

      FALSE_FILTERS = T.let([[0].freeze, [0].freeze].freeze, [T::Array[Integer], T::Array[Integer]])

      sig do
        params(
          filters: InputFilters,
          repo_ids_scope: T.nilable(T::Array[Integer]),
          orgs: T::Array[Organization],
          user: User,
          user_session: UserSession,
          scope: T.nilable(Business),
        ).void
      end
      def initialize(filters, repo_ids_scope:, orgs:, user:, user_session:, scope: nil)
        @filters = filters
        @repo_ids_scope = repo_ids_scope
        @orgs = orgs
        @user = user
        @user_session = user_session
        @scope = scope
      end

      sig { returns([T::Array[Integer], T::Array[Integer]]) }
      def to_filters
        # Prevent consumers from mutating the memoized value
        [
          to_filters_impl.first.dup.sort,
          to_filters_impl.last.dup.sort,
        ]
      end

      private

      sig { returns([T::Array[Integer], T::Array[Integer]]) }
      memoize def to_filters_impl
        return FALSE_FILTERS if @repo_ids_scope&.empty?

        # We do a lot of in-place manipulation of the filters, so we need to duplicate them
        repo_filters = [
          (substrings = @filters.name_substrings.dup),
          (names = @filters.names.dup),
          (visibilities = @filters.visibilities.dup),
          (archived = @filters.archived.dup),
          (topics = @filters.topics.dup),
          (teams = @filters.teams.dup),
          (code_scanning_alerts = @filters.code_scanning_alerts.dup),
          (dependabot_alerts = @filters.dependabot_alerts.dup),
          (secret_scanning_alerts = @filters.secret_scanning_alerts.dup),
        ]
        custom_properties = @filters.custom_properties.dup
        custom_proprties_incl = !(custom_properties.blank? || custom_properties.start_with?("-"))

        return [@repo_ids_scope || [], []] if repo_filters.flatten.empty? && custom_properties.blank?

        values_for_repo_id = T.let([[], []], [T::Array[Integer], T::Array[Integer]])

        # This variable points to the empty array in the return value we're going to populate with repo IDs.
        # Either the inclusive filters or the exclusive filters.
        repo_ids = values_for_repo_id.first

        # If there are no inclusive filters,
        # we need to use the exclusive filters as though they're inclusive filters
        # so we get the repo IDs we should exclude.
        has_incl_filters = @repo_ids_scope.present? || repo_filters.map(&:first).flatten.any? || custom_proprties_incl
        unless has_incl_filters
          # This swaps the inclusive and exclusive filters
          repo_filters.each { |f| f.reverse! }

          # Switch the position of repo_ids to make it the exclusive filters list in the return value
          values_for_repo_id.reverse!
          custom_properties.remove!("-")
        end

        # Fill the chosen array with repo IDs
        base_query = RepositorySecurityCenterConfig.where(owner_id: @orgs)
        if @scope.present? && @scope.is_a?(Business)
          include_emus = ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(@scope) &&
            SecurityProduct::Permissions::BusinessAuthz.new(@scope, actor: @user).can_view_user_owned_repository_alerts?
          base_query = RepositorySecurityCenterConfig
            .with_owners_under_business(@scope, @orgs, include_emus: include_emus)
        end

        repo_ids.concat(
          base_query
            .then do |r|
              next r unless @repo_ids_scope.present?
              r.where(repository_id: @repo_ids_scope)
            end
            .then { |r| Filters::ByRepository.new(*substrings, substring_match: true, scope: @scope).apply(r) }
            .then { |r| Filters::ByRepository.new(*names, scope: @scope).apply(r) }
            .then { |r| Filters::ByVisibility.new(*visibilities).apply(r) }
            .then { |r| Filters::ByArchived.new(*archived).apply(r) }
            .then { |r| Filters::ByTopic.new(*topics, organizations: @orgs).apply(r) }
            .then { |r| Filters::ByTeam.new(*teams, organizations: @orgs, user: @user).apply(r) }
            .then do |r|
              next r if @orgs.size != 1
              Filters::ByCustomProperty.new(
                query: custom_properties,
                org: T.must(@orgs.first),
                user: @user,
                user_session: @user_session,
                allowed_repo_ids: @repo_ids_scope
              ).apply(r)
            end
            .then do |r|
              next r unless code_scanning_alerts.flatten.any? || dependabot_alerts.flatten.any? || secret_scanning_alerts.flatten.any?
              # Using 'group' instead of 'select distinct' because these filters use `having` clauses
              r.left_outer_joins(:repository_security_center_statuses).group(:repository_id)
                .then { |r| Filters::ByFeature.new(*code_scanning_alerts, feature: :code_scanning, scope: @scope).apply(r) }
                .then { |r| Filters::ByFeature.new(*dependabot_alerts, feature: :dependabot_alerts, scope: @scope).apply(r) }
                .then { |r| Filters::ByFeature.new(*secret_scanning_alerts, feature: :secret_scanning, scope: @scope).apply(r) }
            end
            .pluck(:repository_id)
        )

        # Use the repo IDs scope to further limit the repo IDs we're going to return
        unless @repo_ids_scope.nil?
          repo_ids.replace(repo_ids & @repo_ids_scope)

          unless has_incl_filters
            # The repo IDs scope is like having inclusive filters,
            # so we check whether it would be a shorter list of repo IDs
            # to use the repo IDs scope as inclusive filters instead of the exclusive filters.
            reduced_repo_ids_scope = @repo_ids_scope - repo_ids

            # If the reduced repo IDs scope is empty, that means the exclusive filters excluded all the repos in the scope.
            return FALSE_FILTERS if reduced_repo_ids_scope.empty? && @repo_ids_scope.any?

            if reduced_repo_ids_scope.size < repo_ids.size
              values_for_repo_id.reverse! # Switch repo_ids to be the inclusive filters
              repo_ids.replace(reduced_repo_ids_scope)
            end
          end
        end

        # If we have inclusive filters and they resulted in no matched repos,
        # we need to indicate that we should return no results in the final query.
        # So we use conflicting inclusive and exclusive filters to produce the '1=0' clause predicate.
        return FALSE_FILTERS if repo_ids.empty? && has_incl_filters

        values_for_repo_id
      end
    end
  end
end
