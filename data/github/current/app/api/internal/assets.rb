# typed: true
# frozen_string_literal: true

class Api::Internal::Assets < Api::Internal

  require_api_semantic_version "smasher"

  post "/internal/assets/archives", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/data-infrastructure"
    body = verify_and_receive(Hash, required: true) || {}
    ids = Array(body["ids"]).first(100)

    archives = Asset::Archive.all_deleteable(ids).
      map do |arc|
        {
          path_prefix: arc.alambic_path_prefix,
          oid: arc.asset_oid,
        }
      end

    deliver_raw archives
  end
end
