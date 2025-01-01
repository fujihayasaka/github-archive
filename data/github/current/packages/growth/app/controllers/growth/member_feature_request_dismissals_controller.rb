# typed: strict
# frozen_string_literal: true

module Growth
  class MemberFeatureRequestDismissalsController < ApplicationController
    include ApplicationController::VerifiedFetchDependency

    allow_verified_fetch only: [:update]

    before_action :login_required
    before_action :ensure_member_feature_request_exists, only: [:update]
    before_action :authorize_user, only: [:update]

    sig { void }
    def update
      with_database_error_fallback(fallback: -> { service_unavailable_response }) do
        T.must(member_feature_request).dismiss_request!(actor: current_user)
        T.must(member_feature_request).send_dismissal_email(actor: current_user)

        respond_to do |format|
          format.html { head :ok }
          format.json { render json: { message: "Member feature request dismissed successfully" }, status: :ok }
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_to do |format|
        format.html { head :unprocessable_entity }
        format.json { render json: { errors: e.record.errors }, status: :unprocessable_entity }
      end
    end

    private

    sig { returns(T.nilable(MemberFeatureRequest)) }
    memoize def member_feature_request
      MemberFeatureRequest.find_by(id: params[:id])
    end

    sig { void }
    def ensure_member_feature_request_exists
      head :not_found if member_feature_request.nil?
    end

    sig { void }
    def authorize_user
      request_entity = T.must(member_feature_request).request_entity
      if request_entity.organization? && !request_entity.role_of(current_user).admin?
        head :forbidden
      end
    end

    sig { void }
    def service_unavailable_response
      head :service_unavailable
    end

    sig { returns(::User) }
    def target_for_conditional_access
      current_user
    end
  end
end
