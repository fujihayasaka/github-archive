# typed: true
# frozen_string_literal: true

class FilterProviders::IssueFieldsController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  # We rely on the `repository_for_context` method in the index method
  # from the RepositoriesDependency module, which makes use of the CAP filter under the hood.
  # Therefore, we can skip the CAP filter checks on these actions and reduce some of the overhead on the request.
  skip_before_action :perform_conditional_access_checks, only: [:index] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  skip_before_action :ensure_query_value_present # Only applies to show action which we don't have
  around_action :track_request_time, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests

  def index
    unless feature_enabled?
      respond_payload({ issue_fields: [] })
      return
    end

    issue_fields = find_issue_fields.map { |field| format_response(field) }
    respond_payload({ issue_fields: issue_fields })
  end

  private

  def feature_enabled?
    return false unless has_repository_context? && logged_in?

    repo = repositories_for_context.first
    return false unless repo&.owner

    IssueFieldsFeature.enabled?(repo, actor: current_user) ||
      IssueFieldsFeature.enabled?(repo.owner, actor: current_user)
  end

  def find_issue_fields
    repo = repositories_for_context.first
    return [] unless repo&.owner&.is_a?(Organization)

    # Get all issue fields for the organization using domain layer
    all_fields = Issues.domain.issue_fields.by_organization(repo.owner, :name)

    # Apply query filtering if present
    filtered_fields = if query_value.present?
      all_fields.select { |field| field.name.downcase.include?(query_value.downcase) }
    else
      all_fields
    end

    # Apply limit and ensure uniqueness
    filtered_fields
      .first(maximum_result_limit)
      .uniq { |field| field.name.downcase }
  end

  def format_response(field)
    data_type = field.data_type.to_s.upcase

    payload = {
      name: field.name,
      data_type: data_type,
      name_slug: field.name_slug,
    }

    if data_type == "SINGLE_SELECT"
      payload[:options] = field.options&.map { |o| { name: o.name, color: o.color } }
    end

    payload
  end
end
