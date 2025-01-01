# typed: true
# frozen_string_literal: true

class Copilot::Chat::Autocomplete::DiscussionsController < Copilot::Chat::AutocompleteController
  include Suggestions::RepositoryContextDependency

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  def index
    respond_to do |format|
      format.json do
        render json: discussions_payload
      end
    end
  end

  private

  def discussions_payload
    find_discussions.map do |discussion|
      {
        number: discussion.number,
        title: discussion.title,
        repo: repository_context&.name_with_display_owner,
        state: discussion.state,
      }
    end
  end

  memoize def find_discussions
    repo = repository_context
    return [] unless repo.present?

    escaped_query = Search.escape_characters(query_value).strip

    # Unlike the queries for PRs and issues, the discussions query returns no results when the query is empty
    if escaped_query.empty?
      return repo.discussions.filter_spam_for(current_user).newest_first.limit(RESULT_LIMIT)
    end

    Search::Queries::DiscussionQuery.new({
      current_user: @viewer,
      repo_id: repo.id,
      phrase: "in:title #{escaped_query}*",
      source_fields: false,
      per_page: RESULT_LIMIT,
      force_discussion_number_terms: true,
      escape_wildcards: false,
      sort: %w[updated desc],
      ngram_title: true,
      normalizer: ->(results) { results.map { |r| r["_model"] } },
    }).execute.results
  end
end
