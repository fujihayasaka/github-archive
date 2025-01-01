# frozen_string_literal: true

# Wholesale copied from gh/gh ( lib/github/failbot_key_tagger.rb )
module DependencyGraph
  # List of context keys that will become tags
  #
  # TODO: private_repo will be useful but is not an allowed key yet
  TAGGED_SENTRY_KEYS = %w[
    accept
    action
    api_route
    codespace_id
    codespace_azure_message_id
    controller
    current_ref
    catalog_service
    datacenter
    deployed_to
    job
    kube_namespace
    kube_cluster
    language
    migration_id
    processor
    queue
    rails
    release
    region
    repo_id
    request_category
    request_id
    route
    ruby
    server
    site
    spec
    stateless
    twirp_error_code
    user_agent
    zone
  ]

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
        next key unless DependencyGraph::TAGGED_SENTRY_KEYS.include?(key)
        "##{key}"
      end
    end

    def enabled?
      @enabled
    end
  end
end
