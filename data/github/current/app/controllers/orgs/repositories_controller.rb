# typed: true
# frozen_string_literal: true

class Orgs::RepositoriesController < Orgs::Controller
  # The following actions do not require conditional access checks:
  # - index: serves `/orgs/:org`, a simple redirect action that
  #   handles enforcement on the receiving end of the redirection.
  skip_before_action :perform_conditional_access_checks, only: %w(index) # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  # Allow pagination above the cap of 100 for customers with over 100 pages of repositories
  skip_before_action :cap_pagination, only: %i(index), unless: :robot?

  include Orgs::Invitations::RateLimiting
  include ProfilesHelper
  include Orgs::RepoListPayloadHelper
  include TagAttributeHelper
  include Repos::ListHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:repos_list]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    only: [:show, :repos_list],
    optional: true

  def self.react_bundle_name
    "repos-list"
  end

  def index
    redirect_to "/#{this_organization.display_login}"
  end

  def show
    @current_organization = this_organization
    @current_organization.reset_public_members! if GitHub.cache.skip
    set_hovercard_subject(this_organization)

    request&.env[GitHub::TaggingHelper::PROFILE_TYPE] = "organization"
    render_organization_repositories
  end

  def repos_list # rubocop:todo GitHub/UseRestfulActions
    render_404 if this_organization.has_sdn_new_org_with_free_plan_restriction?

    payload = GitHub.dogstats.distribution_time("orgs_repositories_controller.repos_list.payload.time") do
      query_result_payload(repos_query_result, current_user)
    end

    render json: payload
  end

  private

  def search_query
    params[:q] if params[:q].is_a?(String)
  end

  def language_filter
    params[:language] if params[:language].is_a?(String)
  end

  def type_filter
    params[:type] if params[:type].is_a?(String)
  end

  def selected_sort
    params[:sort] if params[:sort].is_a?(String)
  end

  # This is an adaptation of `ProfilesController render_organization_profile`
  # It will fully replace this when the organization profile is completed
  def render_organization_repositories
    GlobalInstrumenter.instrument(
      "user_profile.repositories.page_view",
      profile_user: this_organization,
      profile_viewer: current_user,
      is_organization: true,
      selected_sort: selected_sort.presence,
    )
    if @current_organization.has_sdn_new_org_with_free_plan_restriction?
      render "orgs/restricted_org_notice", locals: {
        target: @current_organization,
        header_view: create_view_model(Orgs::HeaderView, organization: @current_organization),
        selected_nav_item: :repos
      }
    else
      if language_filter.present?
        new_phrase = [search_query, "lang:#{language_filter}"].compact.join(" ")
        return redirect_to action: :show, org: this_organization.display_login, q: new_phrase, type: type_filter
      end

      view = create_view_model(
        Orgs::Repositories::IndexPageView,
        organization: @current_organization,
        current_page: current_page,
        type_filter: params[:type],
        sort_order: selected_sort,
        phrase: search_query,
        rate_limited: org_invite_rate_limited?,
        language: params[:language],
        view_as: params[:view_as],
        cap_filter:,
      )

      payload = GitHub.dogstats.distribution_time("orgs_repositories_controller.show.payload.time") do
        repo_list_payload(current_user, @current_organization, repos_query_result)
      end

      add_client_feature_flag([:repos_list_show_filter_dialog])

      render_react_app(
        payload: payload,
        title: "#{this_organization.display_login} repositories",
        layout: "layouts/orgs/repos_list_tab",
        layout_locals_generator: -> { { view: view } }
      )
    end
  end

  memoize def repos_query_result
    search_org_repos(
      this_organization,
      current_user,
      search_query,
      current_page,
      sort_order: selected_sort,
      user_session:,
      cap_filter:,
    )
  end
end
