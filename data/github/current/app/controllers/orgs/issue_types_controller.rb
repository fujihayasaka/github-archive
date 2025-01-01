# typed: strict
# frozen_string_literal: true

class Orgs::IssueTypesController < Orgs::Controller
  include BranchesHelper
  include RelayHelper
  include InternalGraphqlTracingHelper
  include TagAttributeHelper
  include ResilienceHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_issue_types_enabled
  before_action :ensure_below_issue_type_limit, only: [:new]
  before_action :ensure_issue_type_exists, only: [:edit]

  before_action { @selected_link = T.let(:issue_types_settings, T.nilable(Symbol)) }

  # Required bc client is sending the request using `reactFetch` which doesn't have Rails CSRF token. Enables secure CSRF protection
  allow_verified_fetch only: [:destroy, :create, :update]

  depends_on_clusters ApplicationRecord::Copilot,
    # Rendering the notifications icon synchronously depends on this cluster
    # Can be removed when the feature `notifications_indicator_async_fetch` is released
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :edit, :new],
    optional: true

  # Repository picker query depends on this cluster for permissions
  depends_on_clusters ApplicationRecord::Iam,
    only: [:index]

  # Rendering the organization settings depends on these clusters
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    # Rendering persisted graphql queries depends on this cluster
    ApplicationRecord::Ballast,
    # Rendering the repository picker depends on this cluster
    # Using the `issue_types` feature flag depends on this cluster
    #   Note: This should only be required for the :index action once issue types releases
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    # Rendering enterprise organizations (GHEC / Proxima / GHES) depends on this cluster
    ApplicationRecord::Billing,
    only: [:index, :edit, :new]

  UNAVAILABLE_MESSAGE = "Issue types are currently unavailable. Please try again later."
  ISSUE_TYPE_LIMIT_REACHED = "You have reached the maximum number of issue types. To create a new one, please remove an existing type."

  class QueryPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      @route_id
    end

    sig { params(route_id: String, organization: Organization, pinned_issue_fields: T.nilable(T::Array[Issues::IIssueField]), issue_type: T.nilable(IssueType)).void }
    def initialize(route_id:, organization:, pinned_issue_fields: nil, issue_type: nil)
      @route_id = route_id
      @organization = organization
      @pinned_issue_fields = pinned_issue_fields
      @issue_type = issue_type
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        organization: {
          id: @organization.id,
          login: @organization.display_login
        },
        issueTypes: @organization.issue_types.map(&:to_json_react),
        issueType: @issue_type ? @issue_type.to_json_react : nil,
        pinnedIssueFields: @pinned_issue_fields ? @pinned_issue_fields.map(&:to_json_react) : nil
      }
    end
  end

  sig { void }
  def index
    with_fallback do
      title = "Settings · Issue Types · #{this_organization.display_login}"

      if data_router_enabled?
        payload = QueryPayload.new(route_id: "issueTypesSettingsIndexRoute", organization: this_organization)
        respond_to do |format|
          format.html do
            render_react_html(
              title: title,
              page_data: {
                selected_link: :issue_types
              },
              layout: "layouts/settings/issue_types",
              payload: payload,
            )
          end
          format.json do
            render_react_json(
              title: title,
              payload: payload,
            )
          end
        end
      else
        render_react_app(
          title: title,
          page_data: {
            selected_link: :issue_types
          },
          layout: "layouts/settings/issue_types",
          variable_overwrite_fns: variable_overwrite_fns
      )
      end
    end
  end


  sig { void }
  def edit
    with_fallback do
      title = "Settings · Issue Types · #{this_organization.display_login} · Edit"
      if data_router_enabled?
        @issue_type = T.must(@issue_type)
        payload = QueryPayload.new(route_id: "issueTypesSettingsEditRoute", organization: this_organization, pinned_issue_fields: get_pinned_issue_fields_for(issue_type: @issue_type), issue_type: @issue_type)
        respond_to do |format|
          format.html do
            render_react_html(
              title: title,
              page_data: {
                selected_link: :issue_types
              },
              layout: "layouts/settings/issue_types",
              payload: payload,
            )
          end
          format.json do
            render_react_json(
              title: title,
              payload: payload,
            )
          end
        end
      else
        render_react_app(
          title: title,
          page_data: {
            selected_link: :issue_types
          },
          layout: "layouts/settings/issue_types",
        )
      end
    end
  end

  sig { void }
  def new
    with_fallback do
      title = "Settings · Issue Types · #{this_organization.display_login} · Create"
      if data_router_enabled?
        payload = QueryPayload.new(route_id: "issueTypesSettingsNewRoute", organization: this_organization)
        respond_to do |format|
          format.html do
            render_react_html(
              title: title,
              page_data: {
                selected_link: :issue_types
              },
              layout: "layouts/settings/issue_types",
              payload: payload,
            )
          end
          format.json do
            render_react_json(
              title: title,
              payload: payload,
            )
          end
        end
      else
        render_react_app(
          title: title,
          page_data: {
            selected_link: :issue_types
          },
          layout: "layouts/settings/issue_types",
        )
      end
    end
  end

  sig { void }
  def create
    with_fallback do
      name = params[:name]
      description = params[:description]
      color = params[:color]
      is_enabled = params[:is_enabled]

      issue_type = IssueType.new(owner: this_organization)
      issue_type.name = name if name
      issue_type.description = description if description
      issue_type.color = color.downcase if color
      issue_type.enabled = is_enabled if is_enabled

      result = issue_type.save
      pinned_issue_fields = pin_issue_fields_to(issue_type: issue_type)

      if result
        render json: {
          **issue_type.to_json_react,
          pinned_issue_fields: pinned_issue_fields
        }, status: :ok
      else
        render json: { errors: issue_type.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  sig { void }
  def update
    with_fallback do
      name = params[:name]
      description = params[:description]
      color = params[:color]
      is_enabled = params[:is_enabled]
      id = params[:id]

      issue_type = T.let(IssueType.find_by(id: id, owner: this_organization), T.nilable(IssueType))
      return render_404 unless issue_type

      issue_type.name = name if name
      issue_type.description = description if description
      issue_type.color = color.downcase if color
      issue_type.enabled = is_enabled if is_enabled
      result = issue_type.save

      pinned_issue_fields = pin_issue_fields_to(issue_type: issue_type) if result

      if result && pinned_issue_fields
        render json: {
          **issue_type.to_json_react,
          pinned_issue_fields: pinned_issue_fields
        }, status: :ok
      else
        render json: { errors: issue_type.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  sig { void }
  def destroy
    with_fallback do
      id = params[:id]
      issue_type = T.let(IssueType.find_by(id: id, owner: this_organization), T.nilable(IssueType))
      return render_404 unless issue_type

      result = issue_type.destroy

      if result
        render json: issue_type.to_json_react, status: :ok
      else
        render json: { errors: issue_type.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  private

  sig { void }
  def ensure_below_issue_type_limit
    with_fallback do
      if this_organization.issue_type_limit_reached?
        flash[:error] = ISSUE_TYPE_LIMIT_REACHED
        redirect_back fallback_location: organization_issue_type_settings_path(organization_id: this_organization.display_login)
      end
    end
  end

  sig { void }
  def ensure_issue_type_exists
    with_fallback do
      # Check to see if the issue type exists before loading
      if data_router_enabled?
        @issue_type = T.let(IssueType.find_by(id: params[:id], owner: this_organization), T.nilable(IssueType))
        render_404 unless @issue_type
      else
        begin
          permission = Platform::Authorization::Permission.new(viewer: current_user, origin: Platform::ORIGIN_INTERNAL)
          @issue_type = Platform::Helpers::NodeIdentification.typed_object_from_id(
            [Platform::Objects::IssueType],
            params[:id],
            permission: permission
          )
        rescue Platform::Errors::NotFound
          render_404
        end
      end
    end
  end

  sig { params(block: T.proc.void).void }
  def with_fallback(&block)
    with_database_error_fallback(fallback: nil) do
      return yield
    end

    flash[:error] = UNAVAILABLE_MESSAGE
    redirect_back fallback_location: "/"
  end

  sig { void }
  def ensure_issue_types_enabled
    # as we are checking the access to the org settings page, there is not one specific repo we are checking on
    render_404 unless this_organization.issue_types_enabled?
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def variable_overwrite_fns
    {
      "/organizations/:organization_id/settings/issue-types" => ->(variables) {
        variables[:pageSize] = IssueType::ORGANIZATION_ISSUE_TYPES_LIMIT

        variables
      }
    }
  end

  sig { params(issue_type: IssueType).returns(T::Array[Issues::IIssueField]) }
  def get_pinned_issue_fields_for(issue_type:)
    if pinned_fields_enabled?
      Issues.domain.planning_templates.get_pinned_issue_fields_for_default_template(org: this_organization, issue_type: issue_type, readonly: true)
    else
      []
    end
  end

  sig { params(issue_type: IssueType).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def pin_issue_fields_to(issue_type:)
    return [] unless pinned_fields_enabled?
    return [] unless params[:pinned_issue_field_ids].present?

    begin
      pinned_issue_fields_ids = JSON.parse(params[:pinned_issue_field_ids]).map(&:to_s)
      planning_template = Issues.domain.planning_templates.get_or_create_default_for_org(this_organization)
      issue_fields = Issues.domain.issue_fields
        .by_organization_and_field_ids(ids: pinned_issue_fields_ids, org: this_organization)
        .sort_by { |field| pinned_issue_fields_ids.index(field.id.to_s) }

      Issues.domain.planning_templates.add_bulk_issue_type_fields_mapping(
        org: this_organization,
        issue_type: issue_type,
        issue_fields: issue_fields,
        positions: nil)

      pinned_issue_fields = Issues.domain.planning_templates.get_pinned_issue_fields_for_default_template(org: this_organization, issue_type: issue_type, readonly: false)
      pinned_issue_fields.compact.map(&:to_json_react)
    rescue JSON::ParserError => e
      issue_type.errors.add(:pinned_issue_field_ids, "Invalid JSON format")
      nil
    end
  end

  sig { returns(T::Boolean) }
  memoize def data_router_enabled?
    FeatureFlag.vexi.enabled?("issue_types_settings_data_router", current_user, default: false)
  end

  sig { returns(T::Boolean) }
  memoize def pinned_fields_enabled?
    FeatureFlag.vexi.enabled?("pinned_issue_fields", current_user, default: false)
  end
end
