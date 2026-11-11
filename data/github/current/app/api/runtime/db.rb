# typed: true
# frozen_string_literal: true

##
## Tests for this are at: test/integration/api/runtime/db_test.rb
##

class Api::Runtime::Db < Api::Runtime::SdkBase
  get "/runtime/:app/db/collections/:collection", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_runtime_app!

    collection = params[:collection]

    control_access :runtime_read_kv,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    use_regions = FeatureFlag.vexi.enabled?(:spark_aca_regions, current_user, default: false)
    if use_regions
      region = request.env["HTTP_X_MS_REGION"]
      data = ::SparkRuntime::Kv.get_all_values_for_collection(current_user, runtime_app, collection, region)
    else
      data = ::SparkRuntime::Kv.get_all_values_for_collection(current_user, runtime_app, collection)
    end

    if data.nil?
      deliver_raw([])
    else
      deliver_raw(data)
    end
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    deliver_error!(e.status, message: e.message)
  end
end
