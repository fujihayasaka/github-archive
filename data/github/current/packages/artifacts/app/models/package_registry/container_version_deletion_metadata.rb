# typed: true
# frozen_string_literal: true

module PackageRegistry
  class ContainerVersionDeletionMetadata
    attr_reader :package, :has_single_tagged_version

    delegate :id, :owner, :package_type, :name, :repository, :visibility, :repo_id, :deleted_at, :original_name, to: :package

    def initialize(resp)
      @package = PackageRegistry::Package.new(resp.package) if resp&.package
      @has_single_tagged_version = resp.has_single_tagged_version.nil? ? true : resp&.has_single_tagged_version # true is the safe default which will prevent deletion of a version
    end
  end
end
