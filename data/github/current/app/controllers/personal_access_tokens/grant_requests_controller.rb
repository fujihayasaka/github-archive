# typed: true
# frozen_string_literal: true

class PersonalAccessTokens::GrantRequestsController < ApplicationController
  before_action :login_required
  before_action :require_programmatic_access_tokens_enabled
  before_action :sudo_filter

  before_action :ensure_grant_request, only: [:destroy]

  BETA_VERSION = "beta"
  REQUESTED_MESSAGE = "You've successfully requested additional access for your token"
  UPDATED_MESSAGE = "Your personal access token has been updated"

  def create
    ApplicationRecord::Permissions.transaction do
      options = {
        access: current_access,
        actor: current_user,
        target: current_target,
        permissions: requested_permissions,
        repositories: requested_repositories,
        repository_selection: repository_selection_type,
        skip_expiration_validation: true,
        entry_point: :personal_access_tokens_grant_requests_controller_create,
      }

      if request_reason_params && current_target.organization?
        options[:request_reason] = request_reason_params
      end

      @grant_request = ProgrammaticAccessGrantRequest.create(options)
      raise ActiveRecord::Rollback if @grant_request.errors.any?

      # Attempt to "auto-approve" if @grantable is a request.
      if @grant_request.approvable_by?(current_user)
        @grant = ProgrammaticAccessGrantRequest.approve(@grant_request, current_user, skip_approval_notification: true, entry_point: :personal_access_tokens_grant_requests_controller_create_auto_approve)
        raise ActiveRecord::Rollback if @grant.errors.any?
      end
    end

    grantable_with_errors = if @grant_request.errors.any?
      @grant_request
    elsif @grant && @grant.errors.any?
      @grant
    end

    if grantable_with_errors
      flash[:error] = grantable_with_errors.errors.full_messages.to_sentence
      return redirect_to settings_user_access_tokens_path(current_access)
    end

    flash[:notice] = @grant.present? ? UPDATED_MESSAGE : REQUESTED_MESSAGE
    redirect_to settings_user_tokens_path(type: BETA_VERSION)
  end

  def destroy
    grant_request = ProgrammaticAccessGrantRequest.cancel(current_grant_request, current_user)

    if grant_request && grant_request.errors.any?
      flash[:error] = grant_request.errors.full_messages.to_sentence
      return redirect_to settings_user_access_token_path(current_access)
    end

    redirect_to settings_user_access_token_path(current_access), notice: "Access request cancelled"
  end

  private

  memoize def current_access
    ProgrammaticAccess.for(current_user).find(params[:id])
  end

  memoize def current_grant_request
    ProgrammaticAccessGrantRequest.with_target_and_access(current_target, current_access)
  end

  memoize def current_target
    target = if params.key?(:organization)
      Organization.find_by(login: params[:organization])
    elsif params.key?(:user)
      User.find_by(login: params[:user])
    end

    return render_404 unless target

    target
  end

  def ensure_grant_request
    render_404 unless current_grant_request
  end

  def repository_selection_type
    return :none unless params[:install_target].present?

    target = params[:install_target].to_sym
    target == :selected ? :subset : target
  end

  def request_reason_params
    params[:reason].present? ? params[:reason] : nil
  end

  def requested_permissions
    params
      .require(:integration)
      .permit(default_permissions: {})
      .to_h
      .fetch(:default_permissions)
      .delete_if { |_, action| action.blank? }
      .transform_values!(&:to_sym)
  end

  def requested_repositories
    current_target.repositories.where(id: Array(params[:repository_ids]))
  end

  def require_programmatic_access_tokens_enabled
    render_404 unless current_user.patsv2_enabled?
  end

  def target_for_conditional_access
    current_target
  end
end
