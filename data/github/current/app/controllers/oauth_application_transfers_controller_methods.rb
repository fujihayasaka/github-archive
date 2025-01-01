# typed: true
# frozen_string_literal: true

module OauthApplicationTransfersControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern
  include OauthApplicationsHelper
  include OrganizationsHelper

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    before_action :login_required
    before_action :sudo_filter

    before_action :find_inbound_transfer, only: [:show, :accept]
    before_action :find_transfer,         only: [:destroy]

    before_action :ensure_transfer_cancellable, only: [:destroy]

    helper_method :current_context
  end

  def show
    view = create_view_model(OauthApplicationTransfers::ShowView, transfer: @transfer)
    render "oauth_application_transfers/show", locals: { view: view }
  end

  def accept
    @transfer.finish(current_user)
    flash[:notice] = "Successfully transferred application to #{@transfer.target.display_login}."
    redirect_to oauth_application_path(@transfer.application)
  rescue ActiveRecord::RecordInvalid
    flash[:error] = "Oops! Could not accept that application transfer. Please <a href='#{contact_path}'>contact support</a>."
    redirect_to oauth_applications_path
  end

  def destroy
    @application = @transfer.application
    @transfer.destroy

    flash[:notice] = "Application transfer was canceled."

    if @application.owned_by?(current_user)
      redirect_to settings_user_application_path(@application)
    elsif current_context.organization?
      redirect_to settings_org_applications_path(current_context)
    else
      redirect_to settings_user_applications_path
    end
  end

  private

  # Private: Returns the correct target depending on if we're working
  # with org or user integrations.
  #
  # Returns an Organization or a User
  def current_context
    raise NotImplementedError
  end

  def ensure_transfer_cancellable
    return render_404 unless @transfer.cancelable_by?(current_user)
  end

  def find_inbound_transfer
    @transfer ||= find_inbound_transfer_by_id
    return flash_and_redirect if @transfer.nil?
  end

  def find_inbound_transfer_by_id
    if current_context.organization?
      current_context.inbound_application_transfers.find_by_id(params[:id])
    elsif current_user.display_login == params[:user_id]
      current_user.inbound_application_transfers.find_by_id(params[:id])
    end
  end

  def find_transfer
    @transfer ||= find_transfer_by_id
    return flash_and_redirect if @transfer.nil?
  end

  def find_transfer_by_id
    transfer = find_inbound_transfer_by_id

    return transfer if transfer.present?

    transfer = current_user.outbound_application_transfers.find_by_id(params[:id])
    return transfer if transfer.present? && transfer.target.display_login == params[:user_id]
  end

  def flash_and_redirect
    flash[:error] = "Oops! That application transfer request doesn’t exist or was canceled by the application owner."
    redirect_to_return_to(fallback: oauth_applications_path)
  end
end
