# typed: true
# frozen_string_literal: true

class Copilot::Chat::Autocomplete::IssuesController < Copilot::Chat::AutocompleteController
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
        render json: issues_payload
      end
    end
  end

  private

  def issues_payload
    find_issues.map do |issue|
      {
        number: issue.number,
        title: issue.title,
        repo: repository_context&.name_with_display_owner,
        state: issue.state,
      }
    end
  end

  memoize def find_issues
    repo = repository_context
    return [] unless repo.present?

    Search::Queries::IssueQuery.new({
      current_user: @viewer,
      repo_id: repo.id,
      phrase: "is:issue in:title #{Search.escape_characters(query_value).strip}*",
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
