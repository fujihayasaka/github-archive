# typed: strict
# frozen_string_literal: true

class Orgs::MemberFeatureRequestsController < Orgs::Controller
  extend T::Sig
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  before_action :login_required
  before_action :dotcom_required
  before_action :non_emu_required
  before_action :ensure_user_is_not_business_owner
  before_action :organization_read_or_outside_collaborator_required
  before_action :ensure_admin_is_eligible_to_make_requests

  sig { void }
  def create
    feature = MemberFeatureRequest::Feature.from_string(params[:feature])

    # We query for a fulfilled request so that we can set it to requested.
    member_request = MemberFeatureRequest.find_or_initialize_by(
      requester: current_user,
      request_entity: this_organization,
      billing_entity: (this_organization.adminable_by?(current_user) && this_organization.business) ? this_organization.business : this_organization,
      feature: feature,
      status: :fulfilled
    )

    member_request.status = :requested

    if member_request.save
      head :ok
    else
      render json: { error: member_request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  sig { void }
  def destroy
    GitHub.logger.info(
      "code.namespace" => "Orgs::MemberFeatureRequestsController",
      "code.function" => "destroy",
      "gh.actor.login" => current_user.login, # rubocop:disable GitHub/DoNotAllowLogin login is ok in logs
      "gh.member_feature_request.feature" => params[:feature],
    )
    feature = MemberFeatureRequest::Feature.from_string(params[:feature]) || render_404

    billing_entity = this_organization.adminable_by?(current_user) && this_organization.business ? this_organization.business : this_organization
    MemberFeatureRequest.cancel_request!(current_user, this_organization, feature, billing_entity)

    head :no_content
  end

  private

  sig { void }
  def ensure_user_is_not_business_owner
    return unless (business = this_organization.business)
    head(:forbidden) if business.owner?(current_user)
  end

  sig { void }
  def ensure_admin_is_eligible_to_make_requests
    return unless this_organization.adminable_by?(current_user)
    return if this_organization.business
    head(:forbidden)
  end
end
