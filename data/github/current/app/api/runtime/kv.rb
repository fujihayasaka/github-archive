# typed: true
# frozen_string_literal: true

class Api::Runtime::Kv < Api::App
  before do
    halt 404 unless current_user.feature_enabled?(:copilot_workbench_kv)
  end

  get "/runtime/:app/kv", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_read_kv,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    all_data = get_store_for_app

    deliver_raw(all_data.keys)
  end

  get "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_read_kv,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    key = params[:key]
    all_data = get_store_for_app

    # This response is NOT JSON, just raw contents
    content_type :text
    all_data[key]
  end

  post "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_write_kv,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = request.body.read
    app = params[:app]
    key = params[:key]

    all_data = get_store_for_app
    all_data[key] = data

    Copilot::Runtime::Kv.store.set(app, JSON.dump(all_data))

    deliver_raw({ status: "success" })
  end

  delete "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_write_kv,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    app = params[:app]
    key = params[:key]

    all_data = get_store_for_app
    all_data.delete(key)

    Copilot::Runtime::Kv.store.set(app, JSON.dump(all_data))

    deliver_raw({ status: "success" })
  end

  private

  # To be able to find all keys, we store the whole app's KV in one JSON blob
  def get_store_for_app
    app = params[:app]
    stored = Copilot::Runtime::Kv.store.get(app).value { nil }
    if stored.nil?
      {}
    else
      JSON.parse(stored)
    end
  end
end
