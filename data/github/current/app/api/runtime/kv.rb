# typed: true
# frozen_string_literal: true

##
## Tests for this are at: test/integration/api/runtime/kv_test.rb
##

class Api::Runtime::Kv < Api::Runtime::SdkBase

  get "/runtime/:app/kv", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_runtime_app!

    control_access :runtime_read_kv,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    use_regions = FeatureFlag.vexi.enabled?(:spark_aca_regions, current_user, default: false)
    if use_regions
      region = request.env["HTTP_X_MS_REGION"]
      all_keys = ::SparkRuntime::Kv.all_keys(current_user, runtime_app, region)
    else
      all_keys = ::SparkRuntime::Kv.all_keys(current_user, runtime_app)
    end

    if all_keys.nil?
      deliver_error!(404, message: "No values found")
    end

    deliver_raw(all_keys)
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    deliver_error!(e.status, message: e.message)
  end

  get "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_runtime_app!

    control_access :runtime_read_kv,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    key = params[:key]

    use_regions = FeatureFlag.vexi.enabled?(:spark_aca_regions, current_user, default: false)
    if use_regions
      region = request.env["HTTP_X_MS_REGION"]
      value = ::SparkRuntime::Kv.read_key(current_user, runtime_app, key, region)
    else
      value = ::SparkRuntime::Kv.read_key(current_user, runtime_app, key)
    end

    # This value may be any arbitrary string (JSON or otherwise), so we
    # will simply return it as text
    content_type :text
    value
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    deliver_error!(e.status, message: e.message)
  end

  post "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_runtime_app!

    control_access :runtime_write_kv,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    key = params[:key]
    new_value = request.body.read

    should_limit_payload = FeatureFlag.vexi.enabled?(:copilot_workbench_kv_payload_limit, current_user, default: false)
    size_limit = 512 * 1024 # 512KB
    if should_limit_payload && new_value.bytesize > size_limit
      deliver_error!(413, message: "Value size exceeds limit of #{size_limit} bytes")
    end

    use_regions = FeatureFlag.vexi.enabled?(:spark_aca_regions, current_user, default: false)
    if use_regions
      region = request.env["HTTP_X_MS_REGION"]
      ::SparkRuntime::Kv.write_key(current_user, runtime_app, key, new_value, region)
    else
      ::SparkRuntime::Kv.write_key(current_user, runtime_app, key, new_value)
    end

    deliver_raw({ status: "success" })
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    deliver_error!(e.status, message: e.message)
  rescue SparkRuntime::Kv::SparkRuntimeKvReadOnlyError => e
    deliver_error!(403, message: e.message)
  end

  delete "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_runtime_app!

    control_access :runtime_write_kv,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    key = params[:key]

    use_regions = FeatureFlag.vexi.enabled?(:spark_aca_regions, current_user, default: false)
    if use_regions
      region = request.env["HTTP_X_MS_REGION"]
      ::SparkRuntime::Kv.delete_key(current_user, runtime_app, key, region)
    else
      ::SparkRuntime::Kv.delete_key(current_user, runtime_app, key)
    end

    deliver_empty status: 204
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    deliver_error!(e.status, message: e.message)
  rescue SparkRuntime::Kv::SparkRuntimeKvReadOnlyError => e
    deliver_error!(403, message: e.message)
  end
end
