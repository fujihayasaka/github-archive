# typed: true
# frozen_string_literal: true

class Platform::Models::EnterpriseRepositoryInfo
  include GitHub::Relay::GlobalIdentification
  # Enterprise account owners don't have any implicit permissions
  # to view full Repository information for repos in their enterprise.
  # `Platform::Objects::EnterpriseRepositoryInfo` was created to only allow access
  # to specific pieces of non-sensitive information about repositories in the enterprise.
  # This class is a shim to avoid the checks in `Platform::Security::RepositoryAccess`
  # so that enterprise admins can access that data.

  def legacy_global_id
    repository.legacy_global_id
  end

  def platform_type_name
    "EnterpriseRepositoryInfo"
  end

  attr_reader :business, :repository

  delegate :id, :async_name_with_owner, :name, :private?, :created_at, to: :repository

  # repository - A ::Repository to delegate to.
  # business - A ::Business representing the enterprise account under which the
  #   repository exists.
  def initialize(repository, business)
    @repository = repository
    @business = business
  end
end
