# typed: true
# frozen_string_literal: true

class FilterProviders::IssueFieldsController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  # We rely on the `repository_for_context` method in the index method
  # from the RepositoriesDependency module, which makes use of the CAP filter under the hood.
  # Therefore, we can skip the CAP filter checks on these actions and reduce some of the overhead on the request.
  skip_before_action :perform_conditional_access_checks, only: [:index, :dashboard_index] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  rate_limit_requests \
    if: :request_is_rate_limited?,
    key: :issue_fields_rate_limit_key,
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL

  skip_before_action :ensure_query_value_present # Only applies to show action which we don't have
  before_action :login_required, only: [:dashboard_index]
  around_action :track_request_time, only: [:index, :dashboard_index]

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

    issue_fields = find_issue_fields.map { |field| format_response(field, include_description: true) }
    respond_payload({ issue_fields: issue_fields })
  end

  def dashboard_index # rubocop:todo GitHub/UseRestfulActions
    unless dashboard_feature_enabled?
      respond_payload({ issue_fields: [] })
      return
    end

    fields_by_org = find_issue_fields_by_org
    response = build_dashboard_response(fields_by_org)

    respond_payload(response)
  end

  private

  def feature_enabled?
    return false unless has_repository_context?

    repo = repositories_for_context.first
    return false unless repo&.owner

    IssueFieldsFeature.enabled?(repo, actor: current_user) ||
      IssueFieldsFeature.enabled?(repo.owner, actor: current_user)
  end

  def dashboard_feature_enabled?
    IssueFieldsFeature.issue_fields_global_search_enabled?(current_user)
  end

  def find_issue_fields
    repo = repositories_for_context.first
    return [] unless repo&.owner&.is_a?(Organization)

    # Get all issue fields for the organization using domain layer
    all_fields = Issues.domain.issue_fields.by_organization(repo.owner, :name)

    # Preload associations to avoid N+1 queries for owner access in viewable_by? and options in format_response
    ActiveRecord::Associations::Preloader.new(records: all_fields, associations: [:options, :owner]).call

    # Filter fields based on viewer visibility
    visible_fields = Issues.domain.issue_fields.filter_visible_pinned_fields(all_fields, viewer: current_user, repository_id: repo.id)

    # Apply query filtering if present
    supported_fields = supported_issue_fields(visible_fields)

    filtered_fields = if query_value.present?
      supported_fields.select { |field| issue_field_query_match?(field) }
    else
      supported_fields
    end

    # Apply limit and ensure uniqueness
    filtered_fields
      .first(maximum_result_limit)
      .uniq { |field| field.name.downcase }
  end

  def find_issue_fields_by_org
    orgs = current_user.organizations.first(Issues::Domain::IssueFields::ORGANIZATION_LIMIT)

    result = {}
    orgs.each do |org|
      fields = Issues.domain.issue_fields.by_organization(org)

      # Preload associations to avoid N+1 queries for owner access in viewable_by? and options in format_response
      ActiveRecord::Associations::Preloader.new(records: fields, associations: [:options, :owner]).call

      # Filter fields based on viewer visibility
      visible_fields = Issues.domain.issue_fields.filter_visible_pinned_fields(fields, viewer: current_user)

      supported_fields = supported_issue_fields(visible_fields)

      filtered_fields = if query_value.present?
        supported_fields.select { |field| issue_field_query_match?(field) }
      else
        supported_fields
      end

      result[org] = filtered_fields
    end

    result
  end

  def build_dashboard_response(fields_by_org)
    issue_fields = {}

    fields_by_org.each do |org, fields|
      # Apply limit per organization
      limited_fields = fields.first(maximum_result_limit)

      # Only include organization if it has fields
      if limited_fields.any?
        issue_fields[org.display_login] = {
          fields: limited_fields.map { |field| format_response(field, include_description: true) }
        }
      end
    end

    # Return empty array when no fields found, consistent with disabled feature flag response
    if issue_fields.empty?
      { issue_fields: [] }
    else
      { issue_fields: issue_fields }
    end
  end

  def format_response(field, include_description: true)
    data_type = field.data_type

    payload = {
      name: field.name,
      data_type: data_type,
      name_slug: field.name_slug,
    }

    payload[:description] = field.description if include_description
    payload[:descriptionVariant] = "block" if include_description

    if %w[single_select multi_select].include?(data_type)
      sorted = IssueFieldOption.sorted_options(field.options.to_a)
      payload[:options] = sorted.map { |o| { name: o.name, color: o.color&.upcase } }
    end

    payload
  end

  def supported_issue_fields(fields)
    fields.select do |field|
      next true unless field.data_type == "multi_select"
      IssueFieldsFeature.multi_select_enabled?(field.owner)
    end
  end

  def issue_field_query_match?(field)
    normalized_query = query_value.to_s.downcase.delete_prefix("field.").split(":", 2).first
    field.name.downcase.include?(normalized_query) || field.name_slug.include?(normalized_query)
  end

  def request_is_rate_limited?
    !logged_in?
  end

  def issue_fields_rate_limit_key
    key_base = "#{self.class.to_s.underscore}:#{action_name}"
    actor_identifier = request.env.fetch("HTTP_X_SSL_JA3_HASH", nil)
    actor_identifier = request.remote_ip if actor_identifier.blank?
    "#{key_base}:#{actor_identifier}"
  end
end
