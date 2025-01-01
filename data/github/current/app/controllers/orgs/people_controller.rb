# typed: true
# frozen_string_literal: true

class Orgs::PeopleController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index, :show], optional: true

  include ActionView::Helpers::TextHelper
  include EnterpriseManagedUsersHelper

  before_action :login_required, except: :index
  before_action :organization_admin_required, except: :index

  skip_before_action :cap_pagination, only: %i(index show)
  javascript_bundle :organizations

  include RepositoryControllerMethods
  include Orgs::Invitations::RateLimiting

  def index
    # if an Org is under an Enterprise Managed User enabled business
    # it is NOT viewable by non Enterprise-Managed users (including anonymous
    # requests)
    if this_organization.enterprise_managed_user_enabled?
      return render_404 unless current_user&.enterprise_managed_business == this_organization.business
    end

    set_hovercard_subject(this_organization)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/members_table", locals: {
            view: create_view_model(Orgs::People::IndexPageView,
              organization: this_organization,
              page: current_page,
              query: params[:query]
            )
          }
        elsif this_organization.has_sdn_new_org_with_free_plan_restriction?
          render "orgs/restricted_org_notice", locals: {
            target: this_organization,
            header_view: create_view_model(Orgs::HeaderView, organization: this_organization),
            selected_nav_item: :members
          }
        else
          view = create_view_model(
            Orgs::People::IndexPageView,
            organization: this_organization,
            finished_migration: params[:finished_migration] == "1",
            page: current_page,
            query: params[:query],
            rate_limited: org_invite_rate_limited?,
          )
          render "orgs/people/index", locals: { view: view }
        end
      end
    end
  end

  def show
    return render_404 if person.nil?

    repositories = this_organization.visible_repositories_for(person, limit_visible_internal_repos_to_org: this_organization.feature_enabled?(:limit_internal_repos_for_orgs))

    all_repo_access = this_organization.user_all_repo_role_access(person)

    if params[:query].present?
      repositories = ActiveRecord::Base.connected_to(role: :reading) do
        filter = Organization::RepositoryFilter.new(this_organization, viewer: current_user,
                                                    phrase: params[:query], scope: repositories)
        filter.results
      end
    end

    paginated_repositories = repositories.paginate(page: current_page, per_page: 30)
    override_analytics_location "/orgs/<org-login>/people/<user-name>"

    respond_to do |format|
      format.html do
        if request.xhr?
          return render partial: "orgs/people/repository_list", locals: {
            organization: this_organization,
            person: person,
            repositories: paginated_repositories
          }
        else
          view = create_view_model(
            Orgs::People::ShowView,
            all_repo_access: all_repo_access,
            organization: this_organization,
            person: person,
            paginated_repositories: paginated_repositories,
            repositories_count: repositories.size,
          )
          render "orgs/people/show", locals: {
            view: view,
          }
        end
      end
    end
  end

  private

  def resource_for_conditional_access
    self
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_organization  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_organization
  end
end
