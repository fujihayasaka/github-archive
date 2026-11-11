# typed: strict
# frozen_string_literal: true

# FilteredRepositories is responsible for applying filters from a CodeQualityOrgQuery to
# determine which repositories in an organization should be included or excluded from
# Turboquality requests.
#
# This is based on the logic in SecurityCenter::FilterMappers::ToRepositoryIds, but works for all repositories rather
# than only those with security features enabled. It supports less filtering options, as code quality only supports
# filtering by visibility, team, topic, and custom properties.
class CodeQuality::FilteredRepositories
  class Result < T::Struct
    # The IDs of repositories to include in the results. These are expected to be passed to Turboquality in Protobuf
    # format, so an empty array means "do not filter" rather than "no repositories". When no repositories are expected
    # to be included, invalid will be set to true.
    const :included_repository_ids, T::Array[Integer], default: []
    const :excluded_repository_ids, T::Array[Integer], default: []
    const :repos_count_limited, T::Boolean, default: false
    const :invalid, T::Boolean, default: false

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      return false unless other.is_a?(Result)

      other.included_repository_ids.sort == included_repository_ids.sort &&
        other.excluded_repository_ids.sort == excluded_repository_ids.sort &&
        other.repos_count_limited == repos_count_limited &&
        other.invalid == invalid
    end
  end

  FILTERED_REPOSITORY_IDS_LIMIT = 10000 # The maximum number of repository IDs we're willing to send to the API in a single request

  sig { params(allowed_repository_ids: T.nilable(T::Array[Integer]), query: Search::Queries::CodeQualityOrgQuery, organization: Organization, user: User, user_session: T.untyped).void }
  def initialize(allowed_repository_ids:, query:, organization:, user:, user_session:)
    @allowed_repository_ids = allowed_repository_ids
    @query = query
    @organization = organization
    @user = user
    @user_session = user_session
  end

  sig { returns(Result) }
  def filtered_repository_ids
    # If the allowed_repository_ids is an empty array (but not nil), it means there are no repositories the user has
    # access to
    return Result.new(invalid: true) if !@allowed_repository_ids.nil? && @allowed_repository_ids.empty?
    return Result.new(invalid: true) unless @query.is_valid?

    visibilities = [@query.visibility_values, @query.excluded_visibility_values]
    topics = [@query.topics, @query.excluded_topics]
    teams = [@query.team_names, @query.excluded_team_names]
    repo_filters = [visibilities, topics, teams]

    custom_properties_qualifiers = @query.custom_properties_qualifiers
    custom_properties_is_inclusion = custom_properties_qualifiers.present? && custom_properties_qualifiers.any? { |qualifier, _| !qualifier.start_with?("-") }

    # If there are no filters specified, return all allowed repositories
    return Result.new(included_repository_ids: @allowed_repository_ids || []) if repo_filters.flatten.empty? && custom_properties_qualifiers.empty?

    swapped_filters = false
    if @allowed_repository_ids.nil? && repo_filters.map(&:first).flatten.none? && !custom_properties_is_inclusion
      # If we don't have any inclusion filters, we'll instead use the exclusion filters as inclusion filters and swap
      # the rest of the logic around.
      swapped_filters = true
      repo_filters.each { |f| f.reverse! }

      custom_properties_qualifiers.transform_keys! { |k| k.delete_prefix("-") }
    end

    base_query = Repository.active.where(owner_id: @organization.id)

    included_repository_ids = T.let(base_query
      .then do |r|
        next r unless @allowed_repository_ids.present?
        r.where(id: @allowed_repository_ids)
      end
      .then { |r| filter_visibilities(r, *visibilities) }
      .then { |r| filter_topics(r, *topics) }
      .then { |r| filter_teams(r, *teams) }
      .then { |r| filter_custom_properties(r, custom_properties_qualifiers) }
      .pluck(:id), T::Array[Integer])
    excluded_repository_ids = T.let([], T::Array[Integer])

    unless @allowed_repository_ids.nil?
      # As a defensive measure, ensure we only return repositories that are in the allowed list
      included_repository_ids &= @allowed_repository_ids
    end

    # If there are inclusion filters but no repositories matched, the result is invalid since there are no repos to include
    return Result.new(invalid: true) if included_repository_ids.empty? && !swapped_filters

    repos_count_limited = included_repository_ids.size > FILTERED_REPOSITORY_IDS_LIMIT
    included_repository_ids.slice!(0...FILTERED_REPOSITORY_IDS_LIMIT) if repos_count_limited

    if swapped_filters
      # We used exclusion filters as inclusion filters, so now we just need to swap the included and excluded IDs
      included_repository_ids, excluded_repository_ids = excluded_repository_ids, included_repository_ids
    end

    Result.new(
      included_repository_ids:,
      excluded_repository_ids:,
      repos_count_limited:,
      invalid: false,
    )
  end

  private

  sig { params(scope: ActiveRecord::Relation, included_values: T::Array[String], excluded_values: T::Array[String]).returns(ActiveRecord::Relation) }
  def filter_visibilities(scope, included_values, excluded_values)
    if included_values.present?
      scope = filter_visibility_values(scope, included_values)
    end

    if excluded_values.present?
      scope = filter_visibility_values(scope, excluded_values, negate: true)
    end

    scope
  end

  # This method uses T.untyped since methods like public_scope don't exist on ActiveRecord::Relation, and we can't
  # directly reference types like Repository::GeneratedRelationMethods or Repository::PrivateRelation.
  sig { params(scope: T.untyped, values: T::Array[String], negate: T::Boolean).returns(T.untyped) }
  def filter_visibility_values(scope, values, negate: false)
    values = values.uniq
    values = Search::Queries::CodeQualityOrgQuery::VISIBILITY_VALUES - values if negate
    return scope.none if values.empty?

    filters = values.filter_map do |value|
      case value
      when "public"
        scope.public_scope
      when "private"
        scope.private_not_internal_scope
      when "internal"
        scope.internal_scope
      else
        nil
      end
    end

    filtered_scope = filters.reduce { |combined_scope, visibility_scope| combined_scope.or(visibility_scope) }

    # This should never happen, but just in case and to make Sorbet happy
    return scope.none if filtered_scope.nil?

    filtered_scope
  end

  sig { params(scope: ActiveRecord::Relation, included_topics: T::Array[String], excluded_topics: T::Array[String]).returns(ActiveRecord::Relation) }
  def filter_topics(scope, included_topics, excluded_topics)
    scope = filter_topic_values(scope, included_topics) if included_topics.present?
    scope = filter_topic_values(scope, excluded_topics, negate: true) if excluded_topics.present?
    scope
  end

  sig { params(scope: ActiveRecord::Relation, values: T::Array[String], negate: T::Boolean).returns(ActiveRecord::Relation) }
  def filter_topic_values(scope, values, negate: false)
    topic_ids = Topic.where(name: values).pluck(:id)
    return scope.none if topic_ids.empty?

    query = RepositoryTopic
      .where(state: ::RepositoryTopic.applied_state_values, topic_id: topic_ids)
      .where("repository_id = repositories.id")
      .select("1").arel.exists

    if negate
      scope.where.not(query)
    else
      scope.where(query)
    end
  end

  sig { params(scope: ActiveRecord::Relation, included_team_names: T::Array[String], excluded_team_names: T::Array[String]).returns(ActiveRecord::Relation) }
  def filter_teams(scope, included_team_names, excluded_team_names)
    scope = filter_team_values(scope, included_team_names) if included_team_names.present?
    scope = filter_team_values(scope, excluded_team_names, negate: true) if excluded_team_names.present?
    scope
  end

  sig { params(scope: ActiveRecord::Relation, values: T::Array[String], negate: T::Boolean).returns(ActiveRecord::Relation) }
  def filter_team_values(scope, values, negate: false)
    visible_teams = @organization.visible_teams_for(@user).where(slug: values)

    roles = [:admin, :write]
    repo_ids = visible_teams.flat_map { |team| team.direct_or_inherited_repo_ids(action: roles) }.uniq

    if negate
      scope.where.not(id: repo_ids)
    else
      scope.where(id: repo_ids)
    end
  end

  sig { params(scope: ActiveRecord::Relation, custom_properties_qualifiers: T::Hash[String, T.any(String, T::Array[String])]).returns(ActiveRecord::Relation) }
  def filter_custom_properties(scope, custom_properties_qualifiers)
    return scope if custom_properties_qualifiers.blank?

    custom_properties = Search::Queries::CodeQualityOrgQuery.to_s(custom_properties_qualifiers)

    # It's expensive to filter by custom properties, so to filter custom properties we'll use ElasticSearch to get the
    # IDs of matching repositories, then filter the scope by those IDs.
    es_query = ::Search::Queries::RepoQuery.new(
      binary_fork_filter: true,
      include_forks: true,
      normalizer: lambda { |hits| hits.map { |hit| hit.fetch("_source").fetch("repo_id") } },
      page: 1,
      per_page: FILTERED_REPOSITORY_IDS_LIMIT,
      phrase: ::Search::Queries::SecurityCenter::QueryParser.new(custom_properties).custom_properties_string,
      sort: %w(updated desc),
      source_fields: ["repo_id"],
      skip_permission_check: true,
    )
    es_query.qualifiers[:org].clear.must(@organization.display_login)
    es_query.qualifiers[:user].clear
    es_query.qualifiers[:owner].clear
    es_query.qualifiers[:repo].clear

    ids = es_query.execute(skip_prune_results: true).results

    ids &= @allowed_repository_ids unless @allowed_repository_ids.nil?
    ids.sort

    return scope.none if ids.empty?

    scope.where(id: ids)
  end
end
