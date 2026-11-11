# typed: true
# frozen_string_literal: true

class ContextRegion::TabsController < ApplicationController
  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Profiles,
    ApplicationRecord::Repositories

  before_action :login_required
  before_action :require_valid_crumb

  def show
    tab_payload = context_crumb.tab_payload(user: current_user)
    current_repo = context_crumb.object.is_a?(Repository) ? context_crumb.object : nil
    repo_banners = {}

    if current_repo&.archived?
      repo_banners[:archivedRepoBanner] = { archivedAt: current_repo.archived_at }
    end
    render json: {
      tabs: tab_payload&.tabs || [],
      searchContext: get_search_context_payload,
      repoTypeIcon: current_repo&.repo_type_icon,
      repoBanners: repo_banners
    }
  end

  private

  def require_valid_crumb
    render_404 unless context_crumb
  end

  memoize def context_crumb
    crumb_type = params[:crumb_type]&.to_sym
    return nil unless ContextRegion::Factory.valid_crumb_type?(crumb_type)

    GitHub.dogstats.time("global_navigation.context_region.local_navigation_endpoint", tags: ["context_region_type:#{crumb_type}"]) do
      ContextRegion::Factory.build_from_query_params(
        crumb_type: crumb_type,
        crumb_object_identifier: params[:crumb_object_identifier],
        current_user: current_user,
      )
    end
  end

  def target_for_conditional_access
    object = current_user ? context_crumb&.object : nil
    return :no_target_for_conditional_access unless object # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    case object
    when User, Organization, Business
      object
    when Repository
      object.owner
    when Team
      object.organization
    else
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end

  def get_search_context_payload
    scope = ""
    current_repo_name = ""
    current_repo_nwo = ""
    current_repo_org = ""
    user_id = ""
    current_business = ""

    repo = nil
    if params[:crumb_type] != "repository"
      return {}
    end

    crumb_object = context_crumb&.object
    repo = crumb_object if crumb_object.is_a?(Repository)

    if repo
      scope = "repo:#{repo.name_with_display_owner}"
      current_repo_name = repo.name
      current_repo_nwo = repo.name_with_display_owner

      if repo.organization_id?
        current_repo_org = T.must(repo.owner).display_login
        user_id = repo.owner&.display_login
        business = T.must(repo.owner).business
      else
        user_id = repo.owner&.display_login
        business = repo.owner&.business if repo.owner.respond_to?(:business)
      end

      # Set business context if user is a member
      if current_user.present? && business&.unaffiliated_member?(current_user)
        current_business = business.slug
      end
    end

    {
      scope: scope,
      current_repo_name: current_repo_name,
      current_repo_nwo: current_repo_nwo,
      current_repo_org: current_repo_org,
      user_id: user_id,
      current_business: current_business
    }.filter { |_k, v| v.present? }
  end
end
