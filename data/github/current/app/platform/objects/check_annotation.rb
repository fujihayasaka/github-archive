# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CheckAnnotation < Platform::Objects::Base
      description "A single check annotation."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(_permission, _object)
        # No special API permissions
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_check_run.then do |check_run|
          permission.typed_can_see?("CheckRun", check_run)
        end
      end

      scopeless_tokens_as_minimum

      database_id_field

      field :path, String, "The path that this annotation was made on.", null: false

      def path
        @object.path&.dup&.force_encoding("UTF-8")
      end

      field :path_digest, String, "The hashed path of the file this annotation belongs to", null: false, visibility: :internal

      def path_digest
        Digest::SHA256.hexdigest(path)
      end

      field :location, Objects::CheckAnnotationSpan, "The position of this annotation.", null: false

      def location
        {
          start_position: {
            line: @object.start_line,
            column: @object.start_column,
          },
          end_position: {
            line: @object.end_line,
            column: @object.end_column,
          },
        }
      end

      field :annotation_level, Enums::CheckAnnotationLevel, "The annotation's severity level.", null: true

      field :title, String, "The annotation's title", null: true

      def title
        @object.title&.dup&.force_encoding("UTF-8")
      end

      field :has_title, Boolean, "Whether there's an explicit title in this annotation", null: false, visibility: :internal

      def has_title
        @object.read_attribute(:title).present?
      end

      field :message, String, "The annotation's message.", null: false

      def message
        @object.message&.dup&.force_encoding("UTF-8")
      end

      field :blob_url, Scalars::URI, "The path to the file that this annotation was made on.", null: false

      def blob_url
        @object.async_check_run.then do |check_run|
          check_run.async_repository.then do |repo|
            repo.async_owner.then do |_owner|
              check_run.async_check_suite.then do |_check_suite|
                @object.blob_href
              end
            end
          end
        end
      end

      field :raw_details, String, "Additional information about the annotation.", null: true
      field :suggested_change, String, "Suggested change for targeted line in annotation which can be applied", null: true,
        visibility: :under_development
      field :check_run, Objects::CheckRun, "The check run that this annotation belongs to.", null: true, visibility: :internal, method: :async_check_run
    end
  end
end
