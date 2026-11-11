# typed: true
# frozen_string_literal: true

class Api::Internal::MediaApp < Api::Internal

  require_api_semantic_version "galactus"

  post "/internal/media/transitions", operation_id: :internal do
    @route_owner = "@github/lfs"
    body = verify_and_receive(Hash, required: true) || {}
    transition_id = body["transition_id"].to_i
    blob_id = body["blob_id"].to_i
    op = body["operation"].to_s

    transition = Media::Transition.find_by(id: transition_id) if transition_id > 0

    if !transition
      deliver_error! 400, message: "Media Transition #{transition_id.inspect} does not exist"
    end

    blob = Media::Blob.find_by(id: blob_id) if blob_id > 0
    case transition.verify_blob(op, blob)
    when :operation
      deliver_error! 400, message: "Media Transition #{transition_id.inspect} was not #{op.inspect}"
    when :not_blob, :wrong_network
      deliver_error! 400, message: "Media Transition #{transition_id.inspect} does not match blob #{blob_id.inspect}"
    end

    # This is safe because if this is nil, then verify_blob above returns
    # :not_blob, so we know at this point it must be non-nil.
    blob = T.must(blob)

    deliver_raw(
      oid: blob.oid,
      old_path_prefix: blob.alambic_path_prefix,
      new_path_prefix: "media/#{transition.repository_network_id}",
    )
  end
end
