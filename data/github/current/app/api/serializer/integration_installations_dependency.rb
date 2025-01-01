# typed: true
# frozen_string_literal: true

module Api::Serializer::IntegrationInstallationsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::IntegrationsDependency }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  # Creates a Hash to be serialized to JSON. The Hash represents the collection
  # of Repositories associated with an IntegrationInstallation.
  #
  # data    - The Hash of data to be serialized:
  #           :repositories         - The Array of Repositories.
  #           :total_count          - The Integer count of *all* repositories associated
  #                                   with the IntegrationInstallation. Because the list
  #                                   of repositories is subject to pagination, this
  #                                   number may be larger than the size of the
  #                                   :repositories Array.
  #           :repository_selection - The String representing how many repositories
  #                                   the installation has access to:
  #                                   "selected" or "all".
  # options - Hash
  #
  # Returns a Hash.
  def integration_installation_repositories_hash(data, options = {})
    repositories = data.fetch(:repositories, [])

    repository_hashes = repositories.map do |repo|
      repository_hash(
        repo,
        { current_user: options[:current_user] }.merge(content_options(options)),
      )
    end

    {}.tap do |h|
      h[:total_count] = data[:total_count]
      if data[:repository_selection]
        h[:repository_selection] = data[:repository_selection]
      end
      h[:repositories] = repository_hashes
    end
  end

  def integration_installations_hash(data, options = {})
    integration_installations = data.fetch(:integration_installations, [])
    installation_hashes = integration_installations.map do |installation|
      installation_hash(installation, options)
    end

    {}.tap do |h|
      h[:total_count] = data[:total_count]
      h[:installations] = installation_hashes
    end
  end
end
