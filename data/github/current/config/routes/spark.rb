# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

unless GitHub.enterprise?
  get "/spark", to: "spark/dashboard#show", as: :spark_dashboard
  get "/spark/apps", to: redirect("/spark")
  get "/spark/favorites", to: "spark/favorites#index", as: :spark_favorites_index
  post "/spark/favorites/:id", to: "spark/favorites#create", as: :spark_favorites_create
  delete "/spark/favorites/:id", to: "spark/favorites#destroy", as: :spark_favorites_destroy

  get "/spark/keys", to: "runtime/auth#jwks", as: :spark_runtime_auth_keys
  get "/spark/runtime/auth", to: "runtime/auth#authenticate", as: :spark_runtime_auth

  post "/spark/runtime/token", to: "runtime/tokens#create", as: :spark_runtime_token

  get "/spark/entitlement", to: "spark/entitlements#show", as: :spark_entitlement

  get "/copilot/spark/throttle_status", to: "copilot/spark/throttle_status#index", as: :copilot_spark_throttle_status

  # Manifest for MS Store
  get "/copilot/spark/manifest.json", to: "copilot/workbench/manifest#show"

  # Copilot Workbench Routes
  get "/copilot/spark/workbench", to: "copilot/workbench#index", as: :copilot_workbench_list
  get "/copilot/spark/workbench/:id", to: "copilot/workbench#show", as: :copilot_workbench_show
  post "/copilot/spark/workbench/:id", to: "copilot/workbench#update", as: :copilot_workbench_update
  delete "/copilot/spark/workbench/:id", to: "copilot/workbench#destroy", as: :copilot_workbench_delete
  post "/copilot/spark/workbench/:id/iterations", to: "copilot/workbench/iterations#create", as: :spark_iterations, format: false, defaults: { format: :json }
  patch "/copilot/spark/workbench/:id/iterations/:iteration_id", to: "copilot/workbench/iterations#update", as: :spark_iteration, format: false, defaults: { format: :json }
  get "/copilot/spark/workbench/:id/iterations", to: "copilot/workbench/iterations#index", as: :spark_iterations_index, format: false, defaults: { format: :json }
  post "/copilot/spark/workbench/:id/repository_notifications", to: "copilot/workbench/repository_notification_subscriptions#create", as: :spark_repository_notifications, format: false, defaults: { format: :json }

  # Copilot Workbench UI
  get "/copilot/spark", to: redirect("/spark")
  get "/copilot/spark/new", to: "copilot/workbench/editor#create", as: :spark_new, format: false, defaults: { format: :html }
  post "/copilot/spark", to: "copilot/workbench/editor#create", as: :spark_create, format: false, defaults: { format: :json }
  get "/copilot/spark/:id", to: "copilot/workbench/editor#show", as: :spark_show, format: false, defaults: { format: :html }
  get "/copilot/spark/:id/file/*path", to: "copilot/workbench/editor#show", as: :spark_edit, format: false, defaults: { format: :html }
  get "/copilot/spark/:id/files/*path", to: "copilot/workbench/files#show", as: :spark_file, format: false

  # Copilot-Spark Runtime
  get "/copilot/spark/runtime/data/:id", to: "copilot/workbench/runtime_kv#index", as: :spark_runtime_kv_index
  get "/copilot/spark/runtime/data/:id/:key", to: "copilot/workbench/runtime_kv#show", as: :spark_runtime_kv_show, defaults: { format: :text }
  post "/copilot/spark/runtime/data/:id/:key", to: "copilot/workbench/runtime_kv#update", as: :spark_runtime_kv_update, defaults: { format: :text }
  delete "/copilot/spark/runtime/data/:id/:key", to: "copilot/workbench/runtime_kv#destroy", as: :spark_runtime_kv_destroy
  post "/copilot/spark/runtime/deployment/:id", to: "copilot/workbench/deployment#update", as: :spark_runtime_deployment_update

  post "/copilot/spark/runtime/names", to: "copilot/workbench/runtime_name#check_name", as: :spark_runtime_names_check_name, defaults: { format: :json }

  get "/spark/:owner/:id", to: "copilot/workbench/editor#show", as: :spark_friendly, format: false, defaults: { format: :html }
  get "/spark/:owner/:id/file/*path", to: "copilot/workbench/editor#show", as: :spark_workbench_show, format: false, defaults: { format: :html }

  get "/github-spark", to: redirect("/spark")

  # Signup routes
  get "/github-spark/pro",        to: "copilot/signup/spark_pro#index",  as: :spark_pro_signup
  get "/github-spark/pro/signup", to: "copilot/signup/spark_pro#new",    as: :spark_pro_signup_new
  put "/github-spark/pro/signup", to: "copilot/signup/spark_pro#update", as: :spark_pro_signup_update

  get "/github-spark/pro-plus",        to: "copilot/signup/spark_pro_plus#index",  as: :spark_pro_plus_signup
  get "/github-spark/pro-plus/signup", to: "copilot/signup/spark_pro_plus#new",    as: :spark_pro_plus_signup_new
  put "/github-spark/pro-plus/signup", to: "copilot/signup/spark_pro_plus#update", as: :spark_pro_plus_signup_update
end
