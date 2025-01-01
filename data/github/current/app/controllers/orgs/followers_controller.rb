# typed: true
# frozen_string_literal: true

module Orgs
  class FollowersController < Orgs::Controller
    include ProfilesHelper
    include UserContributionsHelper

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    PAGE_SIZE = 50

    set_statsd_sample_rate 0.01, only: :index

    skip_before_action :cap_pagination, only: :index

    def index
      # We're shortcircuiting this for mannequins as it is causing 500s down the line
      return render_404 if this_organization.mannequin?

      # if an Org is under an Enterprise Managed User enabled business
      # it is NOT viewable by non Enterprise-Managed users (including anonymous
      # requests)
      if this_organization.enterprise_managed_user_enabled?
        return render_404 unless current_user&.enterprise_managed_business == this_organization.business
      end

      set_hovercard_subject(this_organization)

      respond_to do |format|
        format.html do
          if this_organization.has_sdn_new_org_with_free_plan_restriction?
            render "orgs/restricted_org_notice", locals: {
              target: this_organization,
              header_view: create_view_model(Orgs::HeaderView, organization: this_organization),
              selected_nav_item: nil
            }
          else
            render_org_followers
          end
        end
      end
    end

    private

    def render_org_followers
      pagination_opts = {
        page: current_page,
        per_page: PAGE_SIZE,
        # Count without the join to users if possible
        total_entries: this_organization.followers_count_for_viewer(current_user)
      }

      followers = this_organization.
        followers_for_viewer(current_user).
        reorder("followers.created_at DESC").
        paginate(pagination_opts)

      render Profiles::Organization::Tabs::FollowersComponent.new(
        organization: this_organization,
        viewer: current_user,
        followers: followers,
        user_session: user_session,
        current_page: current_page
      )
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_organization.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_organization
    end
  end
end
