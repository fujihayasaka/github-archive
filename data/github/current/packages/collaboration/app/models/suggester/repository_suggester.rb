# typed: true
# frozen_string_literal: true

module Suggester
  class RepositorySuggester
    SUGGESTION_LIMIT = 1000

    # Create a Suggester to provide suggested objects for a given context.
    #
    # viewer  - User seeking suggestions
    # subject - Commit, Issue, PullRequest, or Repository on which suggestions
    #           are to be made
    # query   - String to filter suggestions if provided
    # get_avatars - Boolean to indicate if avatars should be included in the response
    # cap_filter - Conditinal Access Policy filter responsible for using
    #              policies such as Ip Allowlist, 2FA, etc. to filter entities
    #
    # Returns a Suggester instance.
    def initialize(viewer:, subject:, cap_filter: nil, query: "", get_avatars: false)
      @viewer = viewer
      @subject = subject
      @query = query
      @repository = @subject.repository # Note: Repository#repository returns `self`
      @cap_filter = cap_filter
      @get_avatars = get_avatars
    end

    def issues
      if has_query? && GitHub.flipper[:repository_suggester_elastic_search].enabled?(@viewer)
        hash = {
          current_user: @viewer,
          repo_id: @repository&.id,
          ids_to_exclude: [@subject.id],
          phrase: "in:title #{Search.escape_characters(@query).strip}*",
          source_fields: false,
          per_page: SUGGESTION_LIMIT,
          force_issue_number_terms: true,
          escape_wildcards: false,
          sort: %w[updated desc],
          ngram_title: true,
          normalizer: ->(results) { results.map { |r| r["_model"] } },
          context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
        }
        search_result = Search::Queries::IssueQuery.new(hash).execute.results
        return search_result
      end
      issue_ids = @repository.issues.suggestions.not_spammy.reselect(:id)
      issue_ids = issue_ids.where("issues.id != ?", @subject.id) if @subject.is_a?(Issue)
      issue_ids = apply_query(issue_ids, field: "issues.title") if has_query?

      derived_table = Arel::Nodes::As.new(issue_ids.arel, Issue.arel_table)

      @repository.issues
        .suggestions
        .where(id: Issue.select(:id).from(derived_table))
        .unscope(:limit) # The inner query already have the limit clause
    end

    def discussions
      if has_query? && GitHub.flipper[:repository_suggester_elastic_search].enabled?(@viewer)
        hash = {
          current_user: @viewer,
          repo_id: @repository&.id,
          phrase: "in:title #{Search.escape_characters(@query).strip}*",
          source_fields: false,
          per_page: SUGGESTION_LIMIT,
          force_discussion_number_terms: true,
          escape_wildcards: false,
          sort: %w[updated desc],
          ngram_title: true,
          normalizer: ->(results) { results.map { |r| r["_model"] } },
        }
        search_result = Search::Queries::DiscussionQuery.new(hash).execute.results
        return search_result
      end
      discussions = @repository.discussions.suggestions.not_spammy
      discussions = discussions.where.not(id: @subject.id) if @subject.is_a?(Discussion)
      discussions = apply_query(discussions, field: "title") if has_query?
      discussions
    end

    def issues_and_discussions
      (issues + discussions).sort { |a, b| b.updated_at <=> a.updated_at }.slice(0, SUGGESTION_LIMIT) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def mentions
      format = Suggester::MentionSerializer.new(viewer: @viewer, get_avatars: @get_avatars)

      filtered_users = prefill(users)
      filtered_participants = prefill(participants)
      filtered_users = filtered_users - filtered_participants
      format.dump(filtered_users, teams, filtered_participants)
    end

    private

    def suggested_users
      source_users = @repository.mentionable_users_for(
        @viewer,
        limit: Repository::JSON_USER_MENTION_LIMIT,
        fields: ["users.id", :login, :display_login, :suspended_at, :spammy, :spammy_reason, :business_id])

      filter(source_users)
    end

    def suggested_participants
      return [] unless @subject.respond_to?(:participants_for)

      source_participants = if @subject.is_a?(PullRequest)
        @subject.participants_for(@viewer, optimize_repo_access_checks: true, remove_dependabot: false)
      else
        @subject.participants_for(@viewer, optimize_repo_access_checks: true)
      end

      filter(source_participants)
    end

    def suggested_teams
      if (org = @repository.organization)
        org.visible_teams_for(@viewer, fields: [:description, :slug, :id, :organization_id])
      else
        []
      end
    end

    def has_query?
      @query.present?
    end

    def apply_query(relation, field:)
      pattern = "%#{@query.grapheme_clusters.join("%")}%"

      clause = if @query =~ /\A\d+\Z/
        "(CONVERT(#{field} USING utf8mb4) COLLATE utf8mb4_unicode_520_ci LIKE :pattern) OR (number LIKE :pattern)"
      else
        "CONVERT(#{field} USING utf8mb4) COLLATE utf8mb4_unicode_520_ci LIKE :pattern"
      end

      relation.where([clause, pattern: pattern])
    end

    def users
      @cap_filter.authorized_resources(suggested_users)
    end

    def participants
      @cap_filter.authorized_resources(suggested_participants)
    end

    def filter(users)
      filter = BlockedUserFilter.new(viewer: @viewer)
      users.compact.uniq.reject(&filter)
    end

    def prefill(users)
      GitHub::PrefillAssociations.prefill_associations(users, [:profile, { user_status: :organization }])
      users
    end

    def teams
      @cap_filter.authorized_resources(suggested_teams)
    end
  end
end
