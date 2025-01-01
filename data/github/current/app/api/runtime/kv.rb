# typed: true
# frozen_string_literal: true

##
## Tests for this are at: test/integration/api/runtime/kv_test.rb
##

class Api::Runtime::Kv < Api::Runtime::SdkBase

  get "/runtime/:app/kv", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    app = params[:app]

    control_access :runtime_read_kv,
      resource: authed_user,
      user: authed_user, # rubocop:disable GitHub/DisallowEgressUserKey
      app: app,
      verbose_log: @verbose_logging_enabled,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    all_keys = ::SparkRuntime::Kv.all_keys(authed_user, app_user_display_login, app)
    if all_keys.nil?
      deliver_error!(404, message: "No values found")
    end

    deliver_raw(all_keys)
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid database")
  end

  get "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    app = params[:app]
    key = params[:key]

    control_access :runtime_read_kv,
      resource: authed_user,
      user: authed_user, # rubocop:disable GitHub/DisallowEgressUserKey
      app: app,
      verbose_log: @verbose_logging_enabled,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    value = ::SparkRuntime::Kv.read_key(authed_user, app_user_display_login, app, key)

    # This value may be any arbitrary string (JSON or otherwise), so we
    # will simply return it as text
    content_type :text
    value
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid database")
  end

  post "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    app = params[:app]
    key = params[:key]

    control_access :runtime_write_kv,
      resource: authed_user,
      user: authed_user, # rubocop:disable GitHub/DisallowEgressUserKey
      app: app,
      verbose_log: @verbose_logging_enabled,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    new_value = request.body.read
    ::SparkRuntime::Kv.write_key(authed_user, app_user_display_login, app, key, new_value)

    deliver_raw({ status: "success" })
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid database")
  end

  delete "/runtime/:app/kv/:key", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    app = params[:app]
    key = params[:key]

    control_access :runtime_write_kv,
      resource: authed_user,
      user: authed_user, # rubocop:disable GitHub/DisallowEgressUserKey
      app: app,
      verbose_log: @verbose_logging_enabled,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ::SparkRuntime::Kv.delete_key(authed_user, app_user_display_login, app, key)

    deliver_empty status: 204
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid database")
  end
end
