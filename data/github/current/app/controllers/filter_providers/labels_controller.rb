# typed: true
# frozen_string_literal: true

class FilterProviders::LabelsController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab

  def index
    labels = find_labels.map { |label| format_response(label) }
    respond_payload({ labels: labels })
  end

  def show
    if label_from_query
      respond_payload(format_response(label_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  memoize def label_from_query
    return nil unless query_value.present?
    labels_scope.find_by(lowercase_name: query_value.downcase)
  end

  def find_labels
    return [] if !has_repository_context? && !logged_in?

    scope = labels_scope

    if query_value.present?
      scope = scope.where("lowercase_name LIKE ?", like_query_value.downcase)
    end

    scope = scope.order("name").limit(maximum_result_limit)
    Label.smart_sort(scope, false).uniq { |label| label.name.downcase }
  end

  def labels_scope
    repos = repositories_from_query.empty? ? find_top_repositories : repositories_from_query
    repo_ids = repos.map(&:id)

    # Currently we de-dup by name, even though we can have a unique name + color across repos.
    # I believe this is OK, given the name is the important part for the search query.
    Label.where(repository_id: repo_ids)
  end

  def format_response(label)
    {
      name: label.name,
      nameHtml: label.name_html,
      description: label.description,
      color: label.color
    }
  end
end
