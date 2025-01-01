# typed: true
# frozen_string_literal: true

class RepositoryRedirect < ApplicationRecord::Domain::Repositories
  belongs_to :repository, -> { where("active = 1") }
  delete_in_background_with :repository

  REPOSITORY_NAME_FORMAT = %r{(?:[\w\.\-])+/(?:[\w\.\-])+}i
  validates_format_of :repository_name, with: REPOSITORY_NAME_FORMAT

  class RepositoryNameType < ActiveRecord::Type::String
    def serialize(value)
      repository_name = super(value)

      return repository_name unless repository_name.present?
      return repository_name unless User.scope_to_current_tenant?

      owner_login, name = repository_name.split("/")

      return repository_name if User.unique_tenant_login?(owner_login)

      login = User.standardize_login(owner_login, suffix: GitHub::CurrentTenant.get.shortcode)
      "#{login}/#{name}"
    end
  end

  attribute :repository_name, RepositoryRedirect::RepositoryNameType.new

  # Public: Find the new repository for a given name.
  #
  # name - The repository name with owner like "defunkt/dotjs".
  #
  # Returns a Repository object or nil when no redirect exists.
  def self.find_redirected_repository(name)
    return if name.blank? # no need to query for a non-nullable column
    return unless name.valid_encoding?
    return if name.encoding.name == "UTF-8" && name.chars.any? { |c| c.bytes.count > 3 }
    return if name !~ REPOSITORY_NAME_FORMAT # skip anything that's not valid anyway
    redirect = joins(:repository).
      where(repository_name: name).
      order("repository_redirects.created_at DESC").
      first
    redirect && redirect.repository
  end

  # Public: Find the new repository for a given old owner name and network
  #
  # name       - The old owner name
  # repository - The repository whose network to search
  #
  # Returns a Repository object or nil when no redirect exists.
  def self.find_networked_by_old_owner(name, repository)
    redirect = joins(:repository).
      with_prefix("repository_redirects.repository_name", "#{name}/").
      where("repositories.source_id = ?", repository.network_id).
      order("created_at DESC").
      first
    redirect && redirect.repository
  end

  # Public: Finds redirects with active repositories for the old owner name
  def self.active_by_old_owner(name)
    joins(:repository).
    where(repositories: { active: true }).
    with_prefix("repository_redirects.repository_name", "#{name}/").
    order("repository_redirects.created_at DESC")
  end
end
