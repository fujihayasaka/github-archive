# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PackageFiles < Platform::Loader
      def self.load(sha256, repository_id)
        self.with_sha256s([sha256], repository_id).first
      end

      def self.with_guid(guid, repository_id)
        ::Registry::File.joins(package_version: { package: :repository })
          .where("repositories.id = ? AND package_files.guid = ?", repository_id, guid).first
      end

      def self.with_sha256s(sha256s, repository_id)
        ::Registry::File.use_index("index_package_files_on_sha256").joins(package_version: { package: :repository })
          .where("repositories.id = ? AND package_files.sha256 IN (?)", repository_id, sha256s)
      end

      def self.with_version_ids(version_ids)
        ::Registry::File.where(package_version_id: version_ids)
      end

      def self.get_version(version_id)
        ::Registry::PackageVersion.where(id: version_id).first
      end
    end
  end
end
