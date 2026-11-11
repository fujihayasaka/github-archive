# typed: true
# frozen_string_literal: true

class Api::BusinessEnterpriseInstallationUserAccountsUploads < Api::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  # These endpoints are only designed to be called from alambic.
  ROUTES_EXCLUDED_FROM_CAP_CHECKS = [
    ["get", "/businesses/:business_id/user-accounts-uploads/:upload_id"],
    ["patch", "/businesses/:business_id/user-accounts-uploads/:upload_id"],
  ]

  def ip_allowlist_enforceable
    return :no if ROUTES_EXCLUDED_FROM_CAP_CHECKS.include?(
      [request.request_method.downcase, route_pattern]
    )
    :yes
  end

  # Called from alambic to deliver an upload hash after a user uploads directly
  # using the alambic endpoint:
  #
  # GET https://uploads.github.com/businesses/:business_id/user-accounts-uploads
  get "/businesses/:business_id/user-accounts-uploads/:upload_id", operation_id: :internal do
    @route_owner = "@github/licensing"
    business = find_business!
    control_access :write_business_enterprise_installation_user_accounts,
      resource: business,
      allow_integrations: true, allow_user_via_granular_actor: false

    upload = find_upload!(business)
    deliver :enterprise_installation_user_accounts_upload_hash, upload
  end

  # Called from alambic to update the state field of an upload after a user
  # uploads directly using the alambic endpoint:
  #
  # POST https://uploads.github.com/businesses/:business_id/user-accounts-uploads
  patch "/businesses/:business_id/user-accounts-uploads/:upload_id", operation_id: :internal do
    @route_owner = "@github/licensing"
    business = find_business!
    control_access :write_business_enterprise_installation_user_accounts,
      resource: business,
      allow_integrations: true, allow_user_via_granular_actor: false

    upload = find_upload!(business)
    data = receive(Hash)

    if data["state"] == "uploaded"
      saved = upload.track_uploaded
      if saved
        return deliver :enterprise_installation_user_accounts_upload_hash, upload, status: 201
      else
        return deliver_error 422,
          errors: upload.errors
      end
    end

    # Don't allow any other attributes of user accounts uploads to be changed.
    deliver_error 422,
      errors: [],
      documentation_url: "Only user accounts upload state can be changed."
  end

  # Called by GitHub Connect on successful upload, to initiate a sync of the
  # uploaded data with the data stored for an installation.
  patch "/businesses/:business_id/user-accounts-uploads/:upload_id/sync", operation_id: :internal do
    @route_owner = "@github/licensing"
    business = find_business!
    control_access :write_business_enterprise_installation_user_accounts,
      resource: business,
      allow_integrations: true, allow_user_via_granular_actor: false
    require_enterprise_installation!
    upload = find_upload!(business)

    if !upload.uploaded?
      deliver_error! 422, message: "This file wasn't successfully uploaded."
    end

    if !upload.sync_pending?
      deliver_error! 422, message: "This file is not pending synchronization."
    end

    EnterpriseInstallation.synchronize_user_accounts_data \
      business: business,
      installation: current_enterprise_installation,
      upload_id: upload.id,
      actor: current_user

    return deliver :enterprise_installation_user_accounts_upload_hash, upload, status: 202
  end

  def find_business!
    record_or_404 find_business
  end

  def find_business
    Business.where(slug: params[:business_id]).first
  end

  def find_upload!(business)
    record_or_404 find_upload(business)
  end

  def find_upload(business)
    EnterpriseInstallationUserAccountsUpload.find_by \
      id: params[:upload_id], business_id: business.id
  end
end
