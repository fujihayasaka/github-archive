# typed: true
# frozen_string_literal: true

module User::IntegrationInstallationDependency
  extend T::Helpers

  requires_ancestor { User }

  # Internal - Find the intersection of repositories the user
  # has with the provided installation.
  #
  # installation - The IntegrationInstallation used for calculate repository
  #                access.
  #
  # Returns an Array
  def associated_installation_repository_ids(installation)
    T.bind(self, User)

    return [] if self.organization?
    return [] unless installation.installed_on_repositories?

    IntegrationInstallation::UserAssociatedRepositories.with_cache(user: self, installation: installation) do
      # Save ourselves a lookup for associated repo ids if the user can admin the
      # target, including the User's own account and orgs they admin.
      target = installation.target
      if target.adminable_by?(self)
        installation.repository_ids
      else
        associated_repository_ids(repository_ids: installation.repository_ids)
      end
    end
  end

  # Internal - Check if the user can access a given installation.
  #
  # Returns an Boolean
  def can_access_installation?(installation)
    T.bind(self, User)

    return false if self.organization?
    target = installation.target

    return true  if target == self
    return false if target.is_a?(Business)
    return true  if target.adminable_by?(self)

    associated_installation_repository_ids(installation).any?
  end
end
