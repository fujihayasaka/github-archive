# typed: true
# frozen_string_literal: true

class Copilot::Chat::Autocomplete::PullsController < Copilot::Chat::AutocompleteController
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
        render json: pulls_payload
      end
    end
  end

  private

  def pulls_payload
    find_pulls.map do |pr_issue|
      pr = pr_issue.pull_request

      {
        number: pr.number,
        title: pr.title,
        repo: repository_context&.name_with_display_owner,
        state: pr.state,
      }
    end
  end

  memoize def find_pulls
    repo = repository_context
    return [] unless repo.present?

    Search::Queries::IssueQuery.new({
      current_user: @viewer,
      repo_id: repo.id,
      phrase: "is:pr in:title #{Search.escape_characters(query_value).strip}*",
      source_fields: false,
      per_page: RESULT_LIMIT,
      force_issue_number_terms: true,
      escape_wildcards: false,
      sort: %w[updated desc],
      ngram_title: true,
      normalizer: ->(results) { results.map { |r| r["_model"] } },
    }).execute.results
  end
end
