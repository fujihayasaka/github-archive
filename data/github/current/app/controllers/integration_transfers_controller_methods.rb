# typed: true
# frozen_string_literal: true

module IntegrationTransfersControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers

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
    view = create_view_model(IntegrationTransfers::ShowView, transfer: @transfer)
    render "integration_transfers/show", locals: { view: view }
  end

  def accept
    @transfer.finish(current_user, entry_point: :integration_transfers_controller_accept_finish_transfer)
    flash[:notice] = "Successfully transferred GitHub App to #{@transfer.target.display_login}."
    redirect_to gh_settings_app_path(@transfer.integration)
  rescue ActiveRecord::RecordInvalid
    flash[:error] = error_message_for_invalid_transfer(@transfer)
    redirect_to gh_settings_apps_path(current_context)
  end

  def destroy
    integration = @transfer.integration
    @transfer.destroy

    flash[:notice] = "GitHub App transfer was canceled."

    if integration.adminable_by?(current_user)
      redirect_to gh_settings_app_path(integration)
    else
      redirect_to gh_settings_apps_path(current_context)
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

    return @transfer unless @transfer.nil?
    redirect_and_flash
  end

  def find_inbound_transfer_by_id
    if current_context.organization?
      current_context.inbound_integration_transfers.find_by_id(params[:id])
    else
      current_user.inbound_integration_transfers.find_by_id(params[:id])
    end
  end

  def find_transfer
    @transfer = find_transfer_by_id

    return @transfer unless @transfer.nil?
    return redirect_and_flash if current_context.organization?

    # In the event the transfer is to a user,
    # we might be able to cancel it even if it's not marked as (in|out)bound.
    #
    # See https://github.com/github/github/issues/121820 for more details.
    @transfer = IntegrationTransfer.includes(integration: [:owner]).find_by(id: params[:id])

    return redirect_and_flash unless @transfer
    return redirect_and_flash unless T.must(@transfer.integration).organization_owned?

    @transfer
  end

  def find_transfer_by_id
    transfer = find_inbound_transfer_by_id
    return transfer if transfer.present?
    current_user.outbound_integration_transfers.find_by_id(params[:id])
  end

  def redirect_and_flash
    flash[:error] = "Oops! That GitHub App request transfer doesn't exist or was canceled by the App owner."
    redirect_to_return_to(fallback: gh_settings_apps_path(current_context))
  end

  def error_message_for_invalid_transfer(transfer)
    default_message = "Oops! Could not accept that GitHub App transfer."

    # If the transfer failed because the App is invalid, then
    # provide a better error message
    integration = transfer.integration
    return default_message unless integration.invalid?
    "This GitHub Application is invalid, " +
    "please work with the current owner to address these errors before completing the transfer: " +
    integration.errors.full_messages.to_sentence
  end
end
