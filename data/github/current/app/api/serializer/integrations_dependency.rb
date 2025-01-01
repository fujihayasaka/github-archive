# typed: true
# frozen_string_literal: true

module Api::Serializer::IntegrationsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::EnterprisesDependency }
  requires_ancestor { Api::Serializer::RepositoriesDependency }
  requires_ancestor { Api::Serializer::UserDependency }

  def authentication_token_hash(authentication_token, options = {})
    return nil unless authentication_token

    options = Api::SerializerOptions.from(options)

    {}.tap do |hash|
      hash[:token]                = options[:token]
      hash[:expires_at]           = time(authentication_token.expires_at_timestamp)
      hash[:permissions]          = options[:permissions] unless options[:permissions].nil?
      hash[:repository_selection] = options[:repository_selection] unless options[:repository_selection].nil?
      hash[:single_file]          = options[:single_file] if single_file_permission?(options)

      unless options["has_multiple_single_files"].nil? || options["single_file_paths"].nil?
        hash[:has_multiple_single_files] = options[:has_multiple_single_files]
        hash[:single_file_paths] = options[:single_file_paths]
      end

      repositories = Array(options.repositories)

      if repositories.any?
        repository_hashes = repositories.map do |repo|
          repository_hash(
            repo,
            { current_user: nil }.merge(content_options(options)),
          )
        end

        hash[:repositories] = repository_hashes
      end

      hash[:valid_after] = valid_after(options[:valid_after]) if options[:valid_after]
    end
  end

  def lightweight_authentication_token_hash(authentication_token, options = {})
    return nil unless authentication_token

    options = Api::SerializerOptions.from(options)

    hash = {
      token:      options[:token],
      expires_at: time(authentication_token.expires_at_timestamp)
    }

    hash[:valid_after] = valid_after(options[:valid_after]) if options[:valid_after]

    hash
  end

  IntegrationFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on App {
      id
      slug
      owner {
        ...Api::Serializer::UserDependency::SimpleUserFragment
        ...Api::Serializer::EnterprisesDependency::EnterpriseFragment
      }
      name
      description
      url
      htmlUrl
      createdAt
      updatedAt
      defaultPermissions {
        resource
        access
      }
      defaultEvents
    }
  GRAPHQL

  IntegrationFragmentWithClientId = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on App {
      id
      clientId
      slug
      owner {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
      name
      description
      url
      htmlUrl
      createdAt
      updatedAt
      defaultPermissions {
        resource
        access
      }
      defaultEvents
    }
  GRAPHQL

  def graphql_integration_hash(integration_node, options = {})
    show_client_id = options[:current_integration]

    integration = if show_client_id
      IntegrationFragmentWithClientId.new(integration_node)
    else
      IntegrationFragment.new(integration_node)
    end
    return nil unless integration

    # Take the array of AppPermission objects and translate them back into one JSON
    # object
    default_permissions = integration.default_permissions.each_with_object({}) do |permission, hash|
      hash[permission.resource] = permission.access.downcase
    end

    response = {
      id: model_id_for_global_id(integration.id),
      slug: integration.slug,
      node_id: integration.id,
      owner: graphql_simple_owner_hash(integration),
      name: integration.name,
      description: integration.description,
      external_url: integration.url.to_s,
      html_url: integration.html_url.to_s,
      created_at: time(integration.created_at),
      updated_at: time(integration.updated_at),
      permissions: default_permissions,
      events:      integration.default_events,
    }

    if show_client_id
      response[:client_id] = integration.client_id
    end

    response
  end

  def integration_hash(integration, options = {})
    return nil unless integration

    {}.tap do |h|
      h[:id] = integration.id
      h[:client_id] = integration.key
      h[:slug] = integration.slug
      h[:node_id] = global_id_for(integration, options)
      h[:owner] = simple_owner_hash(integration, options)
      h[:name] = integration.name
      h[:description] = integration.description
      h[:external_url] = integration.url
      h[:html_url] = URI::join(GitHub.url, integration.public_app_path).to_s
      h[:created_at] = time(integration.created_at)
      h[:updated_at] = time(integration.updated_at)

      # If we're providing the PEM, then we
      # want to see all of the important credentials.
      if options[:pem].present?
        h[:client_id] = integration.key
        h[:webhook_secret] = integration.hook&.secret
        h[:pem]            = options[:pem]
      end

      # If the secret is provided, we can show it also one
      # time on creation.
      if options[:secret].present?
        h[:client_secret]  = options[:secret]
      end

      h[:permissions] = integration.default_permissions
      h[:events]      = integration.default_events

      if options[:current_integration] == integration
        h[:installations_count] = integration.installations.count
      end
    end
  end

  def installation_hash(installation, options = {})
    return unless installation && installation.integration && installation.target

    options = Api::SerializerOptions.from(options)

    permissions = if installation.target.feature_enabled?(:enterprise_app_installation_management)
      installation.get_cached_permissions
    else
      installation.get_cached_permissions.except(*Business::Resources.subject_types)
    end

    {}.tap do |h|
      h[:id] = installation.id
      h[:client_id] = installation.integration.key

      h[:account] = account(installation.target, content_options(options))
      h[:repository_selection] = installation.get_cached_repository_selection
      h[:access_tokens_url] = url("/app/installations/#{installation.id}/access_tokens", options)
      h[:repositories_url]  = url("/installation/repositories", options)

      h[:html_url] = installation_html_url(installation)
      h[:app_id] = installation.integration_id
      h[:app_slug] = installation.integration.slug
      h[:target_id] = installation.target_id
      h[:target_type] = target_type(installation.target)
      h[:permissions] = permissions
      h[:events] = installation.events
      h[:created_at] = installation.created_at
      h[:updated_at] = installation.updated_at
      h[:single_file_name] = installation.single_file_name
      h[:has_multiple_single_files] = installation.multiple_single_files?
      h[:single_file_paths] = installation.single_file_paths
      h[:suspended_by] = account(installation.suspended_by, options)
      h[:suspended_at] = time(installation.suspended_at)

    end
  end

  def scoped_installation_hash(installation, options = {})
    options = Api::SerializerOptions.from(options)

    scoped_hash = {
      permissions:               installation.permissions,
      repository_selection:      installation.repository_selection,
      single_file_name:          installation.single_file_name,
      repositories_url:          url("/user/repos", options),
      account:                   account(installation.target, content_options(options)),
      has_multiple_single_files: installation.multiple_single_files?,
      single_file_paths:         installation.single_file_paths,
    }

    scoped_hash
  end

  def integration_installation_request_hash(integration_installation_request, options = {})
    options = Api::SerializerOptions.from(options)

    {
      id: integration_installation_request.id,
      node_id: global_id_for(integration_installation_request, options),
      account: account(integration_installation_request.target, content_options(options)),
      requester: simple_user_hash(integration_installation_request.requester, options),
      created_at: time(integration_installation_request.created_at),
    }
  end

  def graphql_simple_owner_hash(integration_fragment)
    integration = if GitHub.multi_tenant_enterprise?
      Integration.find_by(id: model_id_for_global_id(integration_fragment.id))
    end

    if integration.present? && ProximaAppSynchronization.synchronized_third_party?(integration)
      simple_dotcom_app_owner_hash(integration)
    elsif integration_fragment.owner.is_a?(Api::App::PlatformTypes::Enterprise)
      graphql_business_hash(integration_fragment.owner)
    else
      graphql_simple_user_hash(integration_fragment.owner)
    end
  end

  def simple_owner_hash(integration, options = {})
    if ProximaAppSynchronization.synchronized_third_party?(integration)
      simple_dotcom_app_owner_hash(integration, options)
    elsif integration.owner.is_a?(Business)
      simple_business_owner_hash(integration.owner, options)
    else
      simple_user_hash(integration.owner, content_options(options))
    end
  end

  # TODO: This is very much a temporary measure until we can introduce a
  # breaking change that supports multiple owner types (users, orgs,
  # enterprises). Until then, we shove a Business object into a hash that looks
  # a bit like a user.
  #
  # Unlike orgs and users, enterprises don't have a set of public URLs, meaning
  # there's a bunch of empty URL attributes here, which might cause problems
  # for some API users but we have nothing else to give them.
  def simple_business_owner_hash(owner, options = {})
    {
      login: owner.display_login,
      id: owner.id,
      node_id: global_id_for(owner, options),
      avatar_url: avatar(owner),
      gravatar_id: "",
      url: "",
      html_url: "",
      followers_url: "",
      following_url: "",
      gists_url: "",
      starred_url: "",
      subscriptions_url: "",
      organizations_url: "",
      repos_url: "",
      events_url: "",
      received_events_url: "",
      type: "enterprise",
      site_admin: false,
    }
  end

  def simple_dotcom_app_owner_hash(integration, options = {})
    owner_metadata = T.must(DotcomAppOwnerMetadata.find_by(local_app: integration))
    base_path = "https://api.github.com/users/#{owner_metadata.display_login}"

    {
      login: owner_metadata.display_login,
      id: 0,  # Dotcom owner ID is 0 to indicate it is not present in the tenant
      node_id: "", # No global_id_for(owner, options) either
      avatar_url: owner_metadata.avatar_url,
      gravatar_id: "",
      url: base_path,
      html_url: owner_metadata.url,
      followers_url: "#{base_path}/followers",
      following_url: "#{base_path}/following{/other_user}",
      gists_url: "#{base_path}/gists{/gist_id}",
      starred_url: "#{base_path}/starred{/owner}{/repo}",
      subscriptions_url: "#{base_path}/subscriptions",
      organizations_url: "#{base_path}/orgs",
      repos_url: "#{base_path}/repos",
      events_url: "#{base_path}/events{/privacy}",
      received_events_url: "#{base_path}/received_events",
      type: owner_metadata.dotcom_type,
      site_admin: false,
    }
  end

  private

  def account(target, options = {})
    case target
    when Business
      business_hash(target, options)
    when User # works for orgs and users
      user_hash(target, options)
    end
  end

  def installation_html_url(installation)
    case installation.target
    when Business
      "#{GitHub.url}/enterprises/#{installation.target.display_login}/settings/installations/#{installation.id}"
    when Organization
      "#{GitHub.url}/organizations/#{installation.target.display_login}/settings/installations/#{installation.id}"
    when User
      "#{GitHub.url}/settings/installations/#{installation.id}"
    end
  end

  def target_type(target)
    return "Enterprise" if target.is_a?(Business)
    target.organization? ? "Organization" : "User"
  end

  def single_file_permission?(options)
    options[:permissions].present? && options[:permissions].key?("single_file")
  end

  def valid_after(timestamp)
    # ISO 8601 with ms precision
    Time.at(timestamp).utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  end
end
