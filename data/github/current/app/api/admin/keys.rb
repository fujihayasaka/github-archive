# typed: true
# frozen_string_literal: true

class Api::Admin::Keys < Api::Admin

  before do
    deliver_error!(404) unless GitHub.enterprise_only_api_enabled?
  end

  # Get all keys
  get "/admin/keys", operation_id: "enterprise-admin/list-public-keys" do # rubocop:todo GitHub/ControlAccess
    scope = filter_and_sort(PublicKey.verified).includes([:repository, :user, :creator])
    keys = paginate_rel(scope)

    deliver :public_key_hash, keys, detail: true
  end

  # Delete a key
  # rubocop:todo GitHub/ControlAccess
  delete "/admin/keys/:key_id", operation_id: "enterprise-admin/delete-public-key" do
    key = record_or_404(PublicKey.find_by(id: int_id_param!(key: :key_id)))

    key.delete
    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess

  private

  def filter_and_sort(scope)
    # filter by accessed_at
    if (since = time_param!(:since)).present?
      scope = scope.accessed_since(since.getlocal)
    end

    if (sort = params[:sort]).present?
      direction = params[:direction] || "asc"
      scope = scope.sorted_by sort, direction
    end

    scope
  end
end
