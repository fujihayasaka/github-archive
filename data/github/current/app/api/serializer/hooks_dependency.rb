# typed: true
# frozen_string_literal: true

module Api::Serializer::HooksDependency
  # Creates a hook Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #           :full - Boolean specifying we want the extended output.
  #
  # Returns a Hash if the Hook exists, or nil.
  include Kernel
  extend T::Helpers
  requires_ancestor { Api::Serializer }

  def simple_hook_hash(hook, options = {})
    return nil if !hook

    config = hook.masked_config

    {
      type: hook.installation_target_type,
      id: hook.id,
      name: hook.name,
      active: hook.active,
      events: Array(hook.events),
      config: config,
      updated_at: time(hook.updated_at),
      created_at: time(hook.created_at),
    }
  end

  # Creates a global hook Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #
  # Returns a Hash if the Hook exists, or nil.
  def global_hook_hash(hook, options = {})
    return nil if !hook

    simple_hook_hash(hook, options).update \
      url: url("/admin/hooks/#{hook.id}", options),
      ping_url: url("/admin/hooks/#{hook.id}/pings", options)

  end

  # Creates a repository Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #           :full - Boolean specifying we want the extended output.
  #
  # Returns a Hash if the Hook exists, or nil.
  def repo_hook_hash(hook, options = {})
    return nil if !hook

    repo = repo_path(options.merge(repo: hook.installation_target), hook)

    hash = simple_hook_hash(hook, options).update \
      url: url("/repos/#{repo}/hooks/#{hook.id}", options),
      test_url: url("/repos/#{repo}/hooks/#{hook.id}/test", options),
      ping_url: url("/repos/#{repo}/hooks/#{hook.id}/pings", options),
      deliveries_url: url("/repos/#{repo}/hooks/#{hook.id}/deliveries", options)

    hash.update \
      last_response: {
        code: hook.last_status,
        status: hook.last_status_to_label,
        message: hook.last_status_message,
      }

    if hook.name == "cli"
      hash[:ws_url] = "#{GitHub.webhook_forwarder_url}/forward?hook_id=#{hook.id}"
    end

    hash
  end

  # Creates a organization Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #
  # Returns a Hash if the Hook exists, or nil.
  def org_hook_hash(hook, options = {})
    return nil if !hook

    org = hook.installation_target

    hash = simple_hook_hash(hook, options).update \
      url: url("/orgs/#{org.login_for_api(use: options[:serialize_login])}/hooks/#{hook.id}", options),
      ping_url: url("/orgs/#{org.login_for_api(use: options[:serialize_login])}/hooks/#{hook.id}/pings", options),
      deliveries_url: url("/orgs/#{org.login_for_api(use: options[:serialize_login])}/hooks/#{hook.id}/deliveries", options)

    if hook.name == "cli"
      hash[:ws_url] = "#{GitHub.webhook_forwarder_url}/forward?hook_id=#{hook.id}"
    end

    hash.update \
      type: "Organization"
  end

  # Creates a business Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #
  # Returns a Hash if the Hook exists, or nil.
  def business_hook_hash(hook, options = {})
    return nil unless hook

    business = hook.installation_target

    simple_hook_hash(hook, options).update \
      type: "Enterprise", enterprise_id: business.id
  end

  # Creates an integration Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #
  # Returns a Hash if the Hook exists, or nil.
  def integration_hook_hash(hook, options = {})
    return nil if !hook

    integration = hook.installation_target

    options = Api::SerializerOptions.from(options)

    simple_hook_hash(hook, options).tap do |h|
      h[:type]   = "App"
      h[:app_id] = integration.id
      h[:deliveries_url] = url("/app/hook/deliveries", options)
    end
  end

  # Creates a marketplace listing Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #
  # Returns a Hash if the Hook exists, or nil.
  def marketplace_listing_hook_hash(hook, options = {})
    return nil if !hook

    listing = hook.installation_target

    simple_hook_hash(hook, options).update \
      marketplace_listing_id: listing.id
  end

  # Creates a Sponsors listing Hash to be serialized to JSON.
  #
  # hook    - Hook instance.
  # options - Hash
  #
  # Returns a Hash if the Hook exists, or nil.
  def sponsors_listing_hook_hash(hook, options = {})
    return nil if !hook

    listing = hook.installation_target

    simple_hook_hash(hook, options).update \
      sponsors_listing_node_id: global_id_for(listing, options)
  end
end
