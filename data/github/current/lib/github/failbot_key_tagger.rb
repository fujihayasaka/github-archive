# typed: true
# frozen_string_literal: true

module GitHub
  # Converts the keys of a failbot report context to be prefixed with a hash (#)
  #
  # Keys with a hash prefix are used by sentry to identify data to be tagged
  # Keys from a context can already be prefixed with a hash
  #
  # This is the core tag list that is applied to all reports, individual data
  #   can be tagged as part of Failbot#report and Failbot#push
  #   Example: Failbot.push("#tagged_data" => data)
  class FailbotKeyTagger
    def initialize(enabled: false)
      @enabled = enabled
    end

    # Mutates a set of the given context keys to be prefixed with a hash (#)
    def convert_keys!(context)
      return context unless enabled?
      context.transform_keys! do |key|
        next key if key.start_with?("#")
        next key unless TAGGED_KEYS.include?(key)
        "##{key}"
      end
    end

    def enabled?
      @enabled
    end

    # List of context keys that will become tags
    #
    # TODO: private_repo will be useful but is not an allowed key yet
    TAGGED_KEYS = %w[
      accept
      action
      api_route
      catalog_service
      cause_catalog_service
      code.function
      code.namespace
      codespace_azure_message_id
      codespace_id
      controller
      critical
      current_ref
      graphql.operation.name
      graphql_current_field
      graphql_query_hash
      graphql_variables_hash
      host.name
      http.request.header.accept
      http.request.header.accept_language
      http.request.header.user_agent
      http.route
      gh.actor.id
      gh.codespaces.copilot_workspace_id
      gh.codespaces.guid
      gh.codespaces.region
      gh.codespaces.vscs_target
      gh.deployment.ref
      gh.enduser.id
      gh.exception.is_critical
      gh.infra.cloud.region
      gh.infra.datacenter.name
      gh.infra.site
      gh.gist.repo_name
      gh.graphql.catalog_service
      gh.graphql.current_field
      gh.graphql.query_hash
      gh.graphql.referrer.controller_action
      gh.graphql.referrer.http.route
      gh.graphql.variables_hash
      gh.migration_tools.migration.id
      gh.repo.id
      gh.repo.orchestration.id
      gh.repo.orchestration.step_name
      gh.repo.orchestration.type
      gh.request.category
      gh.request_id
      gh.request.is_stateless
      gh.user.id
      job
      k8s.namespace.name
      kube_cluster
      kube_namespace
      language
      operation_name
      processor
      query_owning_catalog_service
      queue
      rails
      rails.controller.action
      rails.controller.name
      rails.version
      referrer_controller_action
      region
      repo_id
      request_category
      request_id
      route
      ruby
      ruby.version
      server
      site
      spec
      stateless
      twirp_error_code
      url_pattern
      user_agent
      zone
    ]
  end
end
