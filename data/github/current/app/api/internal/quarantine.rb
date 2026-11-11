# typed: false
# frozen_string_literal: true

class Api::Internal::Quarantine < Api::Internal
  post "/internal/assets/avatars/quarantine", operation_id: :internal do
    @route_owner = "@github/trust-safety"
    deliver_error! 404, message: "Not enabled for Enterprise" if GitHub.enterprise?

    params = receive_json(request.body.read, type: Hash)

    avatar = Avatar.find_by_id(params["avatar_id"].to_i)

    unless avatar
      return deliver_error! 404, message: "Avatar not found"
    end

    hit = PhotoDnaHit.new(content: avatar, uploader: avatar.uploader)
    unless hit.save
      errors = hit.errors.full_messages.join(", ")
      Failbot.report("PhotoDnaHit failed to save for Avatar with ID #{avatar.id}: #{errors}")
    end

    if avatar.quarantine(reason: params["reason"])
      deliver_empty status: 200
    else
      deliver_error! 500, message: "quarantine not successful"
    end
  end

  delete "/internal/assets/avatars/quarantine", operation_id: :internal do
    @route_owner = "@github/trust-safety"
    deliver_error! 404, message: "Not enabled for Enterprise" if GitHub.enterprise?

    params = receive_json(request.body.read, type: Hash)

    avatar = Avatar.find_by_id(params["avatar_id"].to_i)

    if !avatar
      deliver_error! 404, message: "Avatar not found"
    elsif avatar.unquarantine(reason: params["reason"])
      deliver_empty status: 200
    else
      deliver_error! 500, message: "quarantine not successful"
    end
  end

  post "/internal/assets/quarantined_user_asset", operation_id: :internal do
    @route_owner = "@github/trust-safety"
    deliver_error! 404, message: "Not enabled for Enterprise" if GitHub.enterprise?

    params = receive_json(request.body.read, type: Hash)

    asset = UserAsset.find_by_id(params["asset_id"].to_i)

    unless asset
      return deliver_error! 404, message: "User asset not found"
    end

    hit = PhotoDnaHit.new(content: asset, uploader: asset.uploader)
    unless hit.save
      Failbot.report("PhotoDnaHit record failed to save for UserAsset with ID #{asset.id}")
    end

    if asset.quarantine(reason: params["reason"])
      deliver_empty status: 200
    else
      deliver_error! 500, message: "quarantine not successful"
    end
  end

  delete "/internal/assets/quarantined_user_asset", operation_id: :internal do
    @route_owner = "@github/trust-safety"
    deliver_error! 404, message: "Not enabled for Enterprise" if GitHub.enterprise?

    params = receive_json(request.body.read, type: Hash)

    asset = UserAsset.quarantined.find_by_id(params["asset_id"].to_i)

    if !asset
      deliver_error! 404, message: "User asset not found"
    elsif asset.unquarantine(reason: params["reason"])
      deliver_empty status: 200
    else
      deliver_error! 500, message: "unquarantine not successful"
    end
  end

  def require_request_hmac?
    true
  end
end
