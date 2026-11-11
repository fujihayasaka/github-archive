# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositoryFileSerializer < BaseSerializer
      def scope
        RepositoryFile.preload(:repository, :uploader)
      end

      def as_json(options = {})
        {
          type:              "repository_file",
          url:               url,
          repository:        repository,
          user:              user,
          file_name:         file_name,
          file_content_type: file_content_type,
          file_url:          file_url,
          created_at:        created_at,
        }
      end

      private

      def url
        model.storage_external_url
      end

      def repository
        url_for_association(model, :repository)
      end

      def user
        url_for_association(model, :uploader)
      end

      def file_name
        model.name
      end

      def file_content_type
        model.content_type
      end

      def file_url
        File.join(
          "tarball://root/repository_files",
          "/#{model.id}",
          "/#{file_name}",
        )
      end
    end
  end
end
