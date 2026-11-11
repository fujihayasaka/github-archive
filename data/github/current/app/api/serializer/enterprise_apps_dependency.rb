# typed: true
# frozen_string_literal: true

module Api::Serializer::EnterpriseAppsDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }

  # Creates a hash to be serialized to JSON
  #
  # data - Must be a hash with token and url keys
  #
  def enterprise_installable_organizations_hash(data, options = {})
    org = data
    {
      id: org.id,
      login: org.display_login,
      accessible_repositories_url: url("/enterprises/#{org.business.to_param}/apps/installable_organizations/#{org.to_param}/accessible_repositories", options)
    }
  end

  def enterprise_installable_organization_accessible_repositories_hash(repo, options = {})
    {
      id: repo.id,
      name: repo.name,
      full_name: repo.name_with_owner_for_api
    }
  end

  def enterprise_organization_installation_repositories_hash(data, options = {})
    # For now, the output of these serialization methods happen to be
    # identical. This method simply delegates to allow the REST API endpoint
    # code to remain distinct and a little more approachable.
    enterprise_installable_organization_accessible_repositories_hash(data, options)
  end

  def enterprise_organization_installation_hash(installation, options = {})
    target = installation.target
    {
      id: installation.id,
      app_slug: installation.integration.slug,
      client_id: installation.integration.key,
      repository_selection: installation.get_cached_repository_selection,
      repositories_url: url("/enterprises/#{target.business.to_param}/apps/organizations/#{target.to_param}/installations/#{installation.id}/repositories", options),
      permissions: installation.get_cached_permissions,
      events: installation.events,
      created_at: installation.created_at,
      updated_at: installation.updated_at
    }
  end
end
