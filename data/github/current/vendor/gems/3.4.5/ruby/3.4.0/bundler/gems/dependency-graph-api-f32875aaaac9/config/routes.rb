Rails.application.routes.draw do
  resource :query, only: [:create]

  post "checkpoints", to: "checkpoints#checkpoint"
  get "checkpoints/:id", to: "checkpoints#checkpoint"
  put "checkpoints/:id", to: "checkpoints#set_checkpoint"

  post "errors", to: "errors#report_error"

  mount Services.health.app, at: Services.health.mount_path
  mount Services.snapshots.app, at: Services.snapshots.mount_path
  mount Services.dependency_snapshots.app, at: Services.dependency_snapshots.mount_path
  mount Services.repositories.app, at: Services.repositories.mount_path
  mount Services.repository_dependencies.app, at: Services.repository_dependencies.mount_path
  mount Services.repository_sbom.app, at: Services.repository_sbom.mount_path
  mount Services.experimental.app, at: Services.experimental.mount_path
  mount Services.packages.app, at: Services.packages.mount_path
  mount Services.dgp.app, at: Services.dgp.mount_path

  get "/_ping", to: "status#show"
  get "/boom", to: "status#boom"

  post "/_chatops/:chatop", controller: "chatops", action: :execute_chatop
  get  "/_chatops" => "chatops#list"

  root to: "status#not_found"
end
