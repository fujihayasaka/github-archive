# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The RegistryPackage adapter is used to transform a registry package ActiveRecord object
  # into a Hash document that can be indexed in ElasticSearch.
  #
  class RegistryPackage < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "RegistryPackages"
    end

    def self.mysql_cluster
      ::Registry::Package.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= Registry::Package.includes(:owner).find_by_id(document_id)
    end
    alias :registry_package :model

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    #
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      return if registry_package.migrated?
      return if registry_package.package_type = "docker" && registry_package.package_versions.length == 1 && (registry_package.package_versions[0].version == "docker-base-layer" || registry_package.package_versions[0].version == "vdocker-base-layer")

      @hash = {
        _id:          document_id.to_s,
        _type:        document_type,
        _routing:     registry_package.repository&.id,
        name:         registry_package.name,
        original_name: registry_package.original_name,
        repo_id:      registry_package.repository&.id,
        public:       registry_package.repository&.public? || false,
        visibility:   registry_package.repository&.public? ? "public" : "private",
        business_id:  registry_package.repository&.internal_visibility_business_id,
        summary:      registry_package.latest_version&.summary.to_s,
        body:         registry_package.latest_version&.body.to_s,
        package_type: registry_package.registry_package_type,
        downloads:    registry_package.downloads_total_count,
        versions:     versions(registry_package),
        applied_topics: registry_package.repository&.topics&.pluck(:name) || [],
        created_at:   registry_package.created_at,
        updated_at:   registry_package.updated_at,
        deleted_at:   registry_package.deleted_at,
      }
      @hash
    end

    private

    def versions(registry_package)
      latest = registry_package.latest_version
      registry_package.package_versions.not_deleted.map do |version|
        { version: version.version, latest: (version == latest) }
      end
    end

  end
end
