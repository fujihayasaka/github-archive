module API
  module Types
    class PackageRelease < Types::BaseObject
      description "A versioned software library release"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :clearly_defined_score, Integer, null: true

      field :version, String, method: :name, null: true

      field :package_name, String, null: true

      field :package_manager, Enums::PackageManager, null: true

      field :repository_id, Integer, method: :package_github_repository_id, null: true

      field :repository_nwo, String, null: true

      field :license, String, null: true

      field :published_on, String, null: true

      def published_on
        object.published_at.try { |time| time.utc.to_date.iso8601 }
      end

      field :latest_version, String, null: true

      def latest_version
        release = ::PackageRelease.where(package_name: object.package_name, package_manager: object.package_manager).select(:name).latest
        latest_version = release.name unless release.nil?

        latest_version
      end

      field :is_latest, Boolean, null: true

      def is_latest
        object.version.eql?(latest_version)
      end

      field :dependencies, Connections::Dependencies, max_page_size: 30, null: true, connection: true

      def dependencies
        Queries::DependenciesQuery.new(
          dependent: object
        ).dependencies
      end
    end
  end
end
