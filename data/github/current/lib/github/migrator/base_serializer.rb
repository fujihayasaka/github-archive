# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    UTF8_ENCODING_STR = "UTF-8".freeze

    class BaseSerializer
      include Encoding

      REPOSITORY_METADATA_TYPES = %w[
        CommitComment
        Discussion
        DiscussionCategory
        DiscussionComment
        Issue
        IssueComment
        IssueEvent
        Milestone
        ProtectedBranch
        PullRequest
        PullRequestReview
        PullRequestReviewComment
        PullRequestReviewThread
        Release
        Repository
        RepositoryAdvisory
        RepositoryFile
      ].freeze

      attr_reader :options, :org_metadata_only

      def initialize(options = nil)
        @options = options || {}
        @model_url_service = @options[:model_url_service]
        @org_metadata_only = @options[:org_metadata_only] if @options[:org_metadata_only]
      end

      # Public: Serialize model attributes to a hash.
      #
      # model - Instance of an AR model.
      #
      # Returns a Hash.
      def serialize(model)
        model = update_model_before_serialization(model)
        unless skip_validation_check?(model)
          return unless valid?(model)
        end
        self.model = model
        enforce_encoding(as_json)
      end

      # Public: Enforces encoding of strings in the hash.
      #
      # hash - Hash to enforce encoding on.
      #
      # Returns a hash
      def enforce_encoding(hash)
        hash.each do |key, value|
          if value.is_a?(String)
            hash[key] = ensure_utf8(value)
          elsif value.is_a?(Hash)
            hash[key] = enforce_encoding(value)
          elsif value.is_a?(Array)
            hash[key] = enforce_encoding(value)
          end
        end
      end

      def actor
        options[:actor]
      end

      def owner
        options[:owner]
      end

      # Public: Check if model is valid. Acceptable error messages can be
      # defined in acceptable_error_messages and are subtracted from any
      # validation error messages before determining of the record is valid
      # enough for export.
      #
      # model - Instance of an AR model.
      #
      # Returns true or false.
      def valid?(model)
        # oof. `model.valid?` adds a bunch of queries.
        model.valid?
        validation_error_messages = model.errors.messages

        critical_validation_errors(model).empty?
      end

      # Public: Returns a Hash with validation errors, excluding those in acceptable_error_messages.
      #
      # model - Instance of an AR model.
      def critical_validation_errors(model)
        validation_errors = model.errors
        validation_error_messages = model.errors.messages

        validation_error_messages.each do |attribute, messages|
          acceptable = Array(acceptable_error_messages[attribute])

          # remove period at the end of validation messages
          messages = messages.map { |m| m.chomp(".") }

          unless (messages - acceptable).any?
            validation_errors.delete(attribute.to_sym)
          end
        end

        validation_errors
      end

      def acceptable_error_messages
        {
          commit_id: ["has been locked"],
          body: ["is too long (maximum is 65535 characters)"],
          head_repository_id: ["can't be blank"],
          pinned_api_version: ["is invalid"],
          user: ["is blocked"],
          base: [
            "Repository has been locked for migration",
            "Repository was archived so is read-only",
            "Repository was archived so is read-only and repository has been locked for migration",
            "Repository was archived so is read-only, unable to create comment because issue is locked, and repository has been locked for migration",
            "Repository was archived so is read-only and unable to create comment because issue is locked",
            "Issues are disabled for this repo",
            "Issues are disabled for this repo and repository has been locked for migration",
            "Cannot be modified since it is being converted to a discussion",
            "Cannot be modified since the issue has been converted to a discussion"
          ],
        }
      end

      # Public: A scope (or nil) to use when looking up models to export.
      def scope
      end

      private

      attr_accessor :model

      attr_reader :cache

      def skip_validation_check?(model)
        REPOSITORY_METADATA_TYPES.include?(model.class.name) && model.repository.feature_enabled?(:gh_migrator_skip_export_metadata_validation)
      end

      def time(t)
        t ? t.utc.xmlschema : nil
      end

      def url
        url_for_model(model)
      end

      def created_at
        time(model.created_at)
      end

      def updated_at
        time(model.updated_at)
      end

      def ensure_utf8(content)
        guess_and_transcode(content)
      end

      # Internal: ModelUrlService handles url_for_model and model_for_url lookups.
      # It caches lookups to speed up migrations.
      #
      # Returns a ModelUrlService.
      def model_url_service
        @model_url_service ||= ModelUrlService.new
      end
      delegate :url_for_model, :url_for_association, :model_for_url, to: :model_url_service

      def actor_can_admin?
        actor && actor_is_enterprise_admin? || model.permit?(actor, :admin)
      end

      def actor_is_enterprise_admin?
        GitHub.enterprise? && actor.site_admin?
      end

      # Internal: Override this method to alter model attributes before serialization.
      #
      # Returns a the model after updates.
      def update_model_before_serialization(model)
        model
      end
    end
  end
end
