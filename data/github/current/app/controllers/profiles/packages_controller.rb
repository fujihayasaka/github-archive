# typed: true
# frozen_string_literal: true

module Profiles
  class PackagesController < ApplicationController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Billing,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Iam,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    PAGE_SIZE = 30

    include ProfilesHelper
    include Registry::QueryHelper
    include UserContributionsHelper

    around_action :record_profile_stats, only: :index
    before_action :require_user, only: :index
    before_action :ensure_profile_visible
    skip_before_action :cap_pagination, only: :index

    set_statsd_sample_rate 0.01, only: :index

    javascript_bundle :profile
    stylesheet_bundle :profile

    def index
      return render_404 if this_user.mannequin?
      return render_404 if !PackageRegistryHelper.show_packages? || !PackageRegistryHelper.allow_access_to_actor?(this_user, current_user)

      respond_to do |format|
        format.html do
          instrument_hydro

          render_user_profile
        end
      end
    end

    private

    def render_user_profile
      if request.xhr? && !pjax?
        render_user_packages_tab
      else
        render "users/tabs/packages/index", locals: {
          packages: paged_packages,
          layout_data: Profiles::User::LayoutData.preload(
            profile_user: this_user,
            viewer: current_user,
            active_tab: :packages,
          ),
        }
      end
    end

    def render_user_packages_tab
      render partial: "registry/packages/filtered_packages", locals: {
        owner: current_user,
        packages: paged_packages,
        params: params,
      }
    end

    def paged_packages
      return [] if PackageRegistryHelper.show_packages_blankslate?
      repository = params[:repo_name].present? && this_user.repositories.find_by(name: params[:repo_name])
      results, packages = packages_for_query(
        current_user: current_user,
        user_session: user_session,
        owner: this_user,
        repo_id: repository && (repository.public? || repository.readable_by?(current_user)) ? repository.id : nil,
        query: search_query,
        package_type: ecosystem_param,
        visibility: visibility_param,
        sort: sort_param,
        page: current_page,
        per_page: PAGE_SIZE,
        use_cached_versions: true,
      )

      WillPaginate::Collection.create(current_page, PAGE_SIZE) do |pager|
        pager.replace(packages)
        pager.total_entries ||= results.total_entries
      end
    end

    def require_user
      if this_user.nil?
        render_404
      elsif this_user.organization?
        redirect_to user_path(this_user)
      end
    end

    def instrument_hydro
      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: scoped_organization&.id,
        selected_tab: :PACKAGES,
      )
    end

    def record_profile_stats
      return yield unless logged_in? && this_user && !this_user.organization?

      before = Time.now
      yield
      duration = Time.now - before

      tags = ProfilesController::ShowProfileStats.tags(
        activity_overview_rendered: activity_overview_enabled?,
        subject_user: this_user,
        viewer: current_user,
      )

      GitHub.dogstats.distribution("user.profile.packages.request", duration * 1000, tags: tags)
    end

    def search_query
      return @search_query if defined? @search_query
      raw_query = params[:q]
      raw_query if raw_query.is_a?(String)
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end
  end
end
