# typed: true
# frozen_string_literal: true

# Internal CRUD REST API for reading/writing KV store entries scoped to a repository.
# Uses Issues::KV (backed by ipr_key_values table) for storage.
class Api::Internal::IprKv < Api::Internal
  ROUTE_OWNER = "@github/issues"
  MAX_KEY_LENGTH = 255
  MAX_VALUE_LENGTH = 65535

  def externally_accessible?
    false
  end

  def require_request_hmac?
    true
  end

  # GET /internal/ipr-kv/:repository_id?prefix=... - List keys by prefix
  get "/internal/ipr-kv/:repository_id", operation_id: :internal do
    @route_owner = ROUTE_OWNER

    repo_id = params[:repository_id].to_i
    prefix = params[:prefix]
    validate_repository!(repo_id)
    deliver_error!(400, message: "query parameter 'prefix' is required") if prefix.blank?
    validate_key!(prefix)

    kv = Issues::KV.for_repository_id(repo_id)
    result = kv.mget_prefix(prefix)

    unless result.ok?
      deliver_error!(500, message: "Failed to list keys")
    end

    entries = result.value!
    deliver_raw({ entries: entries }, status: 200)
  end

  # GET /internal/ipr-kv/:repository_id/* - Read a value
  get "/internal/ipr-kv/:repository_id/*", operation_id: :internal do
    @route_owner = ROUTE_OWNER

    repo_id = params[:repository_id].to_i
    key = params[:splat].join("/")
    validate_repository!(repo_id)
    validate_key!(key)

    kv = Issues::KV.for_repository_id(repo_id)
    result = kv.get(key)

    unless result.ok?
      deliver_error!(500, message: "Failed to read key")
    end

    value = result.value!
    if value.nil?
      deliver_error!(404, message: "Key not found")
    end

    deliver_raw({ key: key, value: value }, status: 200)
  end

  # PUT /internal/ipr-kv/:repository_id/* - Set a value
  put "/internal/ipr-kv/:repository_id/*", operation_id: :internal, read_from_replicas: true do
    @route_owner = ROUTE_OWNER

    repo_id = params[:repository_id].to_i
    key = params[:splat].join("/")
    validate_repository!(repo_id)
    validate_key!(key)

    body = parse_request_body!
    value = body["value"]
    deliver_error!(400, message: "property 'value' is required in request body") if value.nil?
    deliver_error!(400, message: "value must be a string") unless value.is_a?(String)
    deliver_error!(400, message: "value exceeds maximum length of #{MAX_VALUE_LENGTH}") if value.length > MAX_VALUE_LENGTH

    ActiveRecord::Base.connected_to(role: :writing) do
      kv = Issues::KV.for_repository_id(repo_id)
      kv.set(key, value)
    end

    deliver_raw({ key: key, value: value }, status: 200)
  rescue GitHub::KV::UnavailableError
    deliver_error!(503, message: "Service unavailable")
  end

  # DELETE /internal/ipr-kv/:repository_id/* - Delete a value
  delete "/internal/ipr-kv/:repository_id/*", operation_id: :internal, read_from_replicas: true do
    @route_owner = ROUTE_OWNER

    repo_id = params[:repository_id].to_i
    key = params[:splat].join("/")
    validate_repository!(repo_id)
    validate_key!(key)

    ActiveRecord::Base.connected_to(role: :writing) do
      kv = Issues::KV.for_repository_id(repo_id)
      kv.del(key)
    end

    deliver_empty(status: 204)
  rescue GitHub::KV::UnavailableError
    deliver_error!(503, message: "Service unavailable")
  end

  private

  def validate_repository!(repository_id)
    repo = ActiveRecord::Base.connected_to(role: :reading) do
      Repository.find_by(id: repository_id)
    end
    deliver_error!(404, message: "Repository not found") unless repo
  end

  def validate_key!(key)
    deliver_error!(400, message: "key must not be blank") if key.blank?
    deliver_error!(400, message: "key exceeds maximum length of #{MAX_KEY_LENGTH}") if key.length > MAX_KEY_LENGTH
  end

  def parse_request_body!
    json = request.body.read
    deliver_error!(400, message: "Request body must be valid JSON") if json.blank?
    GitHub::JSON.parse(json)
  rescue JSON::ParserError, Yajl::ParseError
    deliver_error!(400, message: "Request body must be valid JSON")
  end
end
