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

    render json: {
      tabs: tab_payload&.tabs || []
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
end
