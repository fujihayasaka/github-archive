# typed: true
# frozen_string_literal: true

module Profiles
  class SponsoringsController < ApplicationController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    DEFAULT_PAGE_SIZE = 30

    include ProfilesHelper
    include Registry::QueryHelper
    include UserContributionsHelper
    include Sponsors::SharedControllerMethods

    before_action :sponsorable_required
    around_action :record_profile_stats, only: :index
    before_action :sponsors_required, only: :index
    before_action :ensure_profile_visible
    skip_before_action :cap_pagination, only: :index

    set_statsd_sample_rate 0.01, only: :index

    javascript_bundle :profile
    stylesheet_bundle :profile

    def index
      return render_404 if this_user.mannequin?

      if this_user.organization?
        return render_404 if this_user.deleted?

        @current_organization = this_user
        @current_organization.reset_public_members! if GitHub.cache.skip
        set_hovercard_subject(this_user)
        record_org_profile_visitor_stats
      end

      respond_to do |format|
        format.html do
          instrument_hydro

          if this_user.organization?
            redirect_to org_sponsoring_path(this_user)
          elsif request.xhr? && !pjax?
            render partial: "profiles/sponsorings/sponsoring", locals: {
              user: this_user,
              sponsorships: sponsorships,
              paginated_sponsorships: paginated_sponsorships,
              dependency_count: dependency_count,
              blank_slate_text: blank_slate_text,
              active_sponsoring_count: layout_data.active_sponsoring_count,
              inactive_sponsoring_count: layout_data.inactive_sponsoring_count,
            }
          else
            render "profiles/sponsorings/index", locals: {
              user: this_user,
              layout_data: layout_data,
              sponsorships: sponsorships,
              paginated_sponsorships: paginated_sponsorships,
              dependency_count: dependency_count,
              blank_slate_text: blank_slate_text,
            }
          end
        end
      end
    end

    private

    memoize def layout_data
      Profiles::User::LayoutData.preload(
        profile_user: this_user,
        viewer: current_user,
        active_tab: :sponsoring,
        skip_sponsor_preloads: true,
      )
    end

    memoize def include_sponsors_dependencies?
      return false unless GitHub.sponsors_enabled?
      return false unless logged_in?
      this_user == current_user || this_user.adminable_by?(current_user)
    end

    def instrument_hydro
      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: scoped_organization&.id,
        selected_tab: nil,
      )
    end

    def record_org_profile_visitor_stats
      role = if logged_in?
        if @current_organization.direct_or_team_member?(current_user)
          "member"
        else
          "non_member"
        end
      else
        "anonymous"
      end
      GitHub.dogstats.increment("organization", tags: ["action:profile_view", "role:#{role}"])
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

      GitHub.dogstats.distribution("user.profile.sponsoring.request", duration * 1000, tags: tags)
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present?      # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    memoize def sponsorships
      list = Sponsorship.includes(:tier)
        .where(sponsor_id: this_user.id)
        .sponsor_visible_to(current_user)
        .listing_approved
        .active_or_paid
        # Include `filter_spam_for` as the last scope since it will run queries itself on the already-scoped
        # query, so we want that set of sponsorships to be as small as possible:
        .filter_spam_for(current_user)
        .ranked_for_public_profile

      GitHub::PrefillAssociations.prefill_associations(list, :sponsor)
      GitHub::PrefillAssociations.prefill_associations(list, :sponsorable)
      sponsorables = list.map(&:sponsorable)
      GitHub::PrefillAssociations.prefill_batch_method(sponsorables, :sponsored_by_viewer?, current_user)
      Sponsorship.reject_blocked_sponsorships(list, current_user: current_user)
    end

    memoize def paginated_sponsorships
      sponsorships.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    end

    def dependency_count
      return 0 unless viewing_own_profile?

      only_find_dependencies_from_public_repos = !viewing_own_profile?
      loader = Repository::OwnerDependenciesLoader.new(
        public_only: only_find_dependencies_from_public_repos,
        owner_id: current_user.id,
        viewer: current_user,
      )
      loader.total_dependencies(scope: Repository.public_scope)
    rescue DependencyGraph::Client::GraphQLError
      0
    end

    def blank_slate_text
      if viewing_own_profile?
        "You haven’t sponsored any users yet."
      else
        "#{this_user.display_login} hasn’t sponsored any users yet."
      end
    end
  end
end
