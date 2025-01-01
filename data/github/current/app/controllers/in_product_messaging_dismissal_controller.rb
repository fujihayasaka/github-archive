# typed: true
# frozen_string_literal: true

class InProductMessagingDismissalController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab

  before_action :login_required
  allow_verified_fetch only: [:new]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w[
    InProductMessagingDismissalController#create
  ].freeze

  # POST /track-nudge-dismissal
  def create
    id = params[:id]
    return render json: { success: false }, status: :bad_request unless id.present?

    group = params[:group]&.to_sym
    enterprise_id = params[:enterprise_id].present? ? params[:enterprise_id] : nil
    org_id = params[:org_id].present? ? params[:org_id] : nil

    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.track_nudge_dismissal(id: id, group: group, org_id: org_id, enterprise_id: enterprise_id)
    end

    render json: { success: true }
  end

  private

  # Safe because :login_required
  def resource_for_conditional_access
    # Ensure we have a resource that supports conditional access
    return :no_resource_for_conditional_access unless current_user  # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  # Safe because :login_required
  def target_for_conditional_access
    # Target should always be the current user for in-product messaging
    current_user || :no_target_for_conditional_access  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
