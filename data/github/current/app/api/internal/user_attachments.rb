# typed: true
# frozen_string_literal: true

class Api::Internal::UserAttachments < Api::Internal

  def externally_accessible?
    false
  end

  patch "/internal/user-attachments/assets/:guid", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"

    log("PATCH /internal/user-attachments/assets/:guid called", {
      guid: params[:guid],
    })

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    log("Access control passed for user", {
      user_id: current_user.id,
      user_login: current_user.login,
    })

    asset = UserAsset.find_by(guid: params[:guid])

    if !asset.nil?
      log("Found user asset", {
        asset_guid: asset.guid,
      })

      if !asset.has_access?(current_user)
        log("User asset access check failed", {
          user_id: current_user.id,
          user_login: current_user.login,
          asset_guid: asset.guid,
        })
      end
    else
      log("User asset not found", {
        guid: params[:guid],
      })
    end

    if asset.nil? || !asset.has_access?(current_user)
      deliver_error! 404, message: "Not Found"
    end

    asset = T.must(asset)
    data = receive(Hash)

    if data["state"] == "uploaded"
      saved = asset.track_uploaded

      if saved
        deliver_raw({
          url: asset.storage_external_url
        }, status: 201)
      else
        deliver_error 422, errors: asset.errors
      end
    else
      deliver_error 422, message: "Only uploaded states can be changed."
    end
  end

  private

  def log(reason, data = {})
    GitHub.logger.info(reason, {
      request_id: GitHub.context[:request_id],
    }.merge(data))
  end
end
