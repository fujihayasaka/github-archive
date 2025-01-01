# typed: strict
# frozen_string_literal: true

module Growth
  class NoticeDismissalsController < ApplicationController
    include ApplicationController::VerifiedFetchDependency

    before_action :login_required
    before_action :validate_params, only: [:create]
    allow_verified_fetch only: [:create]

    sig { void }
    def create
      notice_dismissal = Growth::NoticeDismissal.new(current_user)
      notice = params[:notice]
      per_user = ActiveModel::Type::Boolean.new.cast(params.fetch(:per_user, true))
      expires = Time.parse(params[:expires]) if params[:expires]

      with_database_error_fallback(fallback: -> {
        service_unavailable_response
      }) do
        if params[:business_id]
          notice_dismissal.dismiss_business_notice(notice, business_id: params[:business_id].to_i, per_user: per_user, expires: expires)
        elsif params[:organization_id]
          notice_dismissal.dismiss_organization_notice(notice, organization_id: params[:organization_id].to_i, per_user: per_user, expires: expires)
        elsif params[:repository_id]
          notice_dismissal.dismiss_repository_notice(notice, repository_id: params[:repository_id].to_i, per_user: per_user, expires: expires)
        else
          notice_dismissal.dismiss_user_notice(notice, expires: expires)
        end

        respond_to do |format|
          format.html { head :created }
          format.json { render json: { message: "Notice dismissed successfully" }, status: :created }
        end
      end
    end

    private

    sig { void }
    def validate_params
      if params[:notice].blank?
        return bad_request_response("Notice parameter is required")
      end

      id_params = [params[:business_id], params[:organization_id], params[:repository_id]].compact
      if id_params.size > 1
        bad_request_response('Please specify at most one entity type: "business_id", "organization_id" or "repository_id"')
      end
    end

    sig { void }
    def service_unavailable_response
      respond_to do |format|
        format.html { head :service_unavailable }
        format.json { render json: { error: "Service is currently unavailable. Please try again later." }, status: :service_unavailable }
      end
    end

    sig { params(message: String).void }
    def bad_request_response(message)
      respond_to do |format|
        format.html { head :bad_request }
        format.json { render json: { error: message }, status: :bad_request }
      end
    end

    sig { returns(::User) }
    def target_for_conditional_access
      current_user
    end
  end
end
