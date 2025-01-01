# typed: strict
# frozen_string_literal: true

class Orgs::IssueTypesController < Orgs::Controller
  include BranchesHelper
  include RelayHelper
  include InternalGraphqlTracingHelper
  include TagAttributeHelper
  include ResilienceHelper

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_issue_types_enabled
  before_action :ensure_below_issue_type_limit, only: [:new]
  before_action :ensure_issue_type_exists, only: [:edit]

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

  sig { void }
  def index
    with_fallback do
      render_react_app(
        title: "Settings · Issue Types · #{this_organization.display_login}",
        page_data: {
          selected_link: :issue_types
        },
        layout: "layouts/settings/issue_types",
        variable_overwrite_fns: variable_overwrite_fns
      )
    end
  end


  sig { void }
  def edit
    with_fallback do
      render_react_app(
        title: "Settings · Issue Types · #{this_organization.display_login} · Edit",
        page_data: {
          selected_link: :issue_types
        },
        layout: "layouts/settings/issue_types",
      )
    end
  end

  sig { void }
  def new
    with_fallback do
      render_react_app(
        title: "Settings · Issue Types · #{this_organization.display_login} · Create",
        page_data: {
          selected_link: :issue_types
        },
        layout: "layouts/settings/issue_types",
      )
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
      begin
        permission = Platform::Authorization::Permission.new(viewer: current_user, origin: Platform::ORIGIN_INTERNAL)
        issue_type = Platform::Helpers::NodeIdentification.typed_object_from_id(
          [Platform::Objects::IssueType],
          params[:id],
          permission: permission
        )
      rescue Platform::Errors::NotFound
        render_404
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
end
