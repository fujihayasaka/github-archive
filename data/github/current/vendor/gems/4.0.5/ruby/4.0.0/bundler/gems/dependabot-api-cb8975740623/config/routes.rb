# frozen_string_literal: true

Rails.application.routes.draw do
  router = Coach::Router.new(self)

  get "/_ping", to: Coach::Handler.new(Routes::Ping)

  if ENV.fetch("CHATOPS_SERVICE", false)
    post "/_chatops/:chatop", controller: "chatops", action: :execute_chatop
    get  "/_chatops" => "chatops#list"
  end

  # Running as a badge service is mutually exclusive with serving our other
  # endpoints.
  if Prius.get(:badge_service)
    router.draw(
      Routes::Badges,
      base: "/badges",
      actions: [
        { compatibility_score: { method: :get, url: "/compatibility_score" } },
      ],
    )
  else
    unless Prius.get(:actions_deployment)
      router.draw(
        Routes::GitHubWebhooks,
        base: "/github_webhooks",
        actions: [
          :create,
          { discard: { method: :post, url: "/discard" } },
        ],
      )
    end

    router.draw(
      Routes::UpdateJobs,
      base: "/update_jobs",
      actions: [
        { credentials: { method: :get, url: "/:id/credentials" },
          create_jit_access: { method: :post, url: "/:id/create_jit_access" },
          details: { method: :get, url: "/:id/details" },
          record_update_job_error: {
            method: :post,
            url: "/:id/record_update_job_error",
          },
          record_update_job_unknown_error: {
            method: :post,
            url: "/:id/record_update_job_unknown_error",
          },
          record_update_job_warning: {
            method: :post,
            url: "/:id/record_update_job_warning",
          },
          create_pull_request: { method: :post, url: "/:id/create_pull_request" },
          update_pull_request: { method: :post, url: "/:id/update_pull_request" },
          close_pull_request: { method: :post, url: "/:id/close_pull_request" },
          create_dependency_submission: {
            method: :post,
            url: "/:id/create_dependency_submission",
          },
          mark_as_processed: { method: :patch, url: "/:id/mark_as_processed" },
          update_dependency_list: {
            method: :post,
            url: "/:id/update_dependency_list",
          },
          record_ecosystem_versions: {
            method: :post,
            url: "/:id/record_ecosystem_versions",
          },
          record_ecosystem_meta: {
            method: :post,
            url: "/:id/record_ecosystem_meta",
          },
          record_cooldown_meta: {
            method: :post,
            url: "/:id/record_cooldown_meta",
          },
          increment_metric: {
            method: :post,
            url: "/:id/increment_metric",
          },
          record_metrics: {
            method: :post,
            url: "/:id/record_metrics",
          }, },
      ],
    )

    router.draw(
      Routes::AutofixSuggestionJobs,
      base: "/autofix_suggestion_jobs",
      actions: [
        { upload_sarif: { method: :post, url: "/:id/sarif" } },
      ]
    )

    # Only expose twirp routes when we are running inside of GitHub
    # infrastructure (including GHES deployments).
    if ENV.fetch("INTERNAL_DEPLOYMENT", false)
      mount Services.update_config.app, at: Services.update_config.mount_path
      mount Services.update_jobs.app, at: Services.update_jobs.mount_path
      mount Services.health.app, at: Services.health.mount_path
      mount Services.repositories_service.app, at: Services.repositories_service.mount_path
      mount Services.repository_access.app, at: Services.repository_access.mount_path
      mount Services.debug_service.app, at: Services.debug_service.mount_path unless Dependabot.enterprise?
      mount Services.secret_service.app, at: Services.secret_service.mount_path
      mount Services.suggested_fixes_service.app, at: Services.suggested_fixes_service.mount_path

      unless Prius.get(:proxima_stamp)
        router.draw(
          Routes::Proxima,
          base: "/proxima",
          actions: [
            { sync: { method: :get, url: "/sync" } },
          ]
        )
      end
    end
  end

  # The only way to get consistent 404 rendering in Rails 3+ is to define a
  # catch all route. This ensures that all bad routes are rendered as 404s.
  #
  # WARNING: This route must be the last route in the routes file.
  match "*unmatched_route",
        to: ->(_) { [404, { "content-type" => "text/plain" }, ["Not Found"]] },
        via: %i(head options get post put patch delete trace connect)
end
