# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module FilterMappers
    class ToRepositoryIds
      include GitHub::Memoizer

      class InputFilters < T::Struct
        const :name_substrings, [T::Array[String], T::Array[String]], default: [[], []]
        const :names, [T::Array[String], T::Array[String]], default: [[], []]
        const :visibilities, [T::Array[String], T::Array[String]], default: [[], []]
        const :archived, [T::Array[String], T::Array[String]], default: [[], []]
        const :topics, [T::Array[String], T::Array[String]], default: [[], []]
        const :teams, [T::Array[String], T::Array[String]], default: [[], []]
        const :custom_properties, String, default: ""
        const :artifact_registries, T::Array[String], default: []
        const :artifact_registry_urls, [T::Array[String], T::Array[String]], default: [[], []]
        const :runtime_risks, T::Array[String], default: []
        const :deployment_record_presence, T::Array[String], default: []
      end

      FALSE_FILTERS = T.let([[0].freeze, [0].freeze].freeze, [T::Array[Integer], T::Array[Integer]])

      sig do
        params(
          filters: InputFilters,
          repo_ids_scope: T.nilable(T::Array[Integer]),
          orgs: T::Array[Organization],
          user: User,
          user_session: T.nilable(UserSession),
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
          (artifact_registries = @filters.artifact_registries),
          (artifact_registry_urls = @filters.artifact_registry_urls.dup),
          (runtime_risks = @filters.runtime_risks),
          (deployment_record_presence = @filters.deployment_record_presence)
        ]
        custom_properties_qualifiers = ::Search::Queries::SecurityCenter::QueryParser.new(@filters.custom_properties).custom_properties_qualifiers
        custom_properties_incl = custom_properties_qualifiers.present? && custom_properties_qualifiers.any? { |qualifier, _| !qualifier.start_with?("-") }

        return [@repo_ids_scope || [], []] if repo_filters.flatten.empty? && custom_properties_qualifiers.blank?

        values_for_repo_id = T.let([[], []], [T::Array[Integer], T::Array[Integer]])

        # This variable points to the empty array in the return value we're going to populate with repo IDs.
        # Either the inclusive filters or the exclusive filters.
        repo_ids = values_for_repo_id.first

        # If there are no inclusive filters,
        # we need to use the exclusive filters as though they're inclusive filters
        # so we get the repo IDs we should exclude.
        has_incl_filters = @repo_ids_scope.present? || repo_filters.map(&:first).flatten.any? || custom_properties_incl
        unless has_incl_filters
          # This swaps the inclusive and exclusive filters
          repo_filters.each { |f| f.reverse! }

          # Switch the position of repo_ids to make it the exclusive filters list in the return value
          values_for_repo_id.reverse!
          # Make all custom properties qualifiers an inclusive filter
          custom_properties_qualifiers.transform_keys! { |k| k.delete_prefix("-") }
        end

        custom_properties = ::Search::Queries::SecurityCenter::Base.to_s(custom_properties_qualifiers)

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
            .then { |r| Filters::ByArtifactRegistry.new(artifact_registries, organizations: @orgs).apply(r) }
            .then { |r| Filters::ByArtifactRegistryUrl.new(*artifact_registry_urls, organizations: @orgs).apply(r) }
            .then { |r| Filters::ByRuntimeRisk.new(runtime_risks, organizations: @orgs).apply(r) }
            .then { |r| Filters::ByDeploymentRecordPresence.new(deployment_record_presence, organizations: @orgs).apply(r) }
            .then do |r|
              next r if @orgs.size != 1
              Filters::ByCustomProperty.new(
                query: custom_properties,
                org: T.must(@orgs.first),
                allowed_repo_ids: @repo_ids_scope
              ).apply(r)
            end
            .pluck(:repository_id)
        )

        # Use the repo IDs scope to further limit the repo IDs we're going to return
        unless @repo_ids_scope.nil?
          repo_ids.replace(repo_ids & @repo_ids_scope)
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
