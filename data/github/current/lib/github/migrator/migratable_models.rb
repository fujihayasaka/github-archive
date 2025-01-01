# typed: true
# frozen_string_literal: true

require "github/migrator/base_archiver"
require "github/migrator/base_serializer"
require "github/migrator/base_post_processor"

require "github/migrator/attachment_archiver"
require "github/migrator/attachment_importer"
require "github/migrator/attachment_serializer"
require "github/migrator/commit_comment_importer"
require "github/migrator/commit_comment_serializer"
require "github/migrator/issue_comment_importer"
require "github/migrator/issue_comment_serializer"
require "github/migrator/issue_importer"
require "github/migrator/issue_event_importer"
require "github/migrator/issue_event_serializer"
require "github/migrator/issue_post_processor"
require "github/migrator/issue_serializer"
require "github/migrator/milestone_importer"
require "github/migrator/milestone_serializer"
require "github/migrator/organization_importer"
require "github/migrator/organization_serializer"
require "github/migrator/project_serializer"
require "github/migrator/project_importer"
require "github/migrator/protected_branch_importer"
require "github/migrator/protected_branch_serializer"
require "github/migrator/pull_request_importer"
require "github/migrator/pull_request_post_processor"
require "github/migrator/pull_request_serializer"
require "github/migrator/pull_request_review_importer"
require "github/migrator/pull_request_review_serializer"
require "github/migrator/repository_archiver"
require "github/migrator/repository_importer"
require "github/migrator/repository_post_processor"
require "github/migrator/repository_serializer"
require "github/migrator/repository_file_archiver"
require "github/migrator/repository_file_importer"
require "github/migrator/repository_file_serializer"
require "github/migrator/repository_advisory_serializer"
require "github/migrator/release_archiver"
require "github/migrator/release_importer"
require "github/migrator/release_serializer"
require "github/migrator/review_comment_importer"
require "github/migrator/review_comment_serializer"
require "github/migrator/review_thread_serializer"
require "github/migrator/team_importer"
require "github/migrator/team_serializer"
require "github/migrator/user_importer"
require "github/migrator/user_serializer"
require "github/migrator/discussion_serializer"
require "github/migrator/discussion_category_serializer"
require "github/migrator/discussion_comment_serializer"
module GitHub
  class Migrator

    # MigratableModel provides serializer, importer, and other data that
    # GitHub::Migrator needs to work with a model object during the export and
    # import processes.
    class MigratableModel
      def initialize(model_type, options = {})
        @model_type         = model_type
        @serializer         = options[:serializer]
        @archiver           = options[:archiver]
        @importer           = options[:importer]
        @post_processor     = options[:post_processor]
        @mapping_actions    = Array(options[:mapping_actions])
        @recommended_action = options[:recommended_action]
        @cache_url_lookups  = options[:cache_url_lookups]
      end

      # Public: Snakecase model name of model this instance represents.
      #
      # Returns a String.
      attr_reader :model_type

      def model_class
        self.class.const_get(model_type.classify)
      end

      # Public: Serializer class for this model.
      #
      # Returns a class constant.
      attr_reader :serializer

      # Public: File archiver class for this model.
      #
      # Returns a class constant.
      attr_reader :archiver

      # Public: Build an archiver, if we have a class for one.
      def build_archiver(*args)
        archiver && archiver.new(*args)
      end

      # Public: Importer class for this model.
      #
      # Returns a class constant.
      attr_reader :importer

      # Public: PostProcessor class for this model.
      #
      # Returns a class constant.
      attr_reader :post_processor

      # Public: List of mapping actions this model supports.
      #
      # Returns an Array.
      attr_reader :mapping_actions

      # Public: Should source to target url lookups be cached for this model?
      #
      # Returns a Boolean.
      attr_reader :cache_url_lookups

      # Public: Should this MigratableModel be checked for conflicts?
      #
      # Returns a TrueClass or FalseClass.
      def check_for_conflicts?
        (mapping_actions - [:map]).any?
      end

      # Public: The recommended mapping action for this model.
      #
      # Returns a Symbol or NilClass.
      attr_reader :recommended_action
    end

    # MigratableModels encapsulates the logic GitHub::Migrator needs for
    # working with various models by providing a MIGRATABLE_MODELS constant
    # and a #migratable_model_for method for looking up a MigratableModel.
    #
    # The order of MIGRATABLE_MODELS is important, the migratable models are
    # listed in the order they need to migrated to ensure that relationships
    # between models are set correctly.
    module MigratableModels

      # Public: Finds a MigratableModel for model_type. Caches MigratableModels
      # in a hash key'd by model_type for quick access.
      #
      # model_type - String model_type.
      #
      # Returns a MigratableModel.
      def migratable_model_for(model_type)
        @migratable_models ||= MIGRATABLE_MODELS.inject({}) do |result, mm|
          result[mm.model_type] = mm
          result
        end

        @migratable_models[model_type]
      end

      # This keeps mannequins out of GitHub Enterprise
      if GitHub.enterprise?
        USER_MAPPING_ACTIONS = %i(map rename map_or_rename conflict).freeze
      else
        USER_MAPPING_ACTIONS = %i(map rename map_or_rename conflict skip).freeze
      end

      MIGRATABLE_MODELS = [
        GitHub::Migrator::MigratableModel.new(
          "user",
          serializer:          GitHub::Migrator::UserSerializer,
          importer:            GitHub::Migrator::UserImporter,
          mapping_actions:     USER_MAPPING_ACTIONS,
          recommended_action:  :map,
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "bot",
          serializer:          GitHub::Migrator::UserSerializer,
          mapping_actions:     USER_MAPPING_ACTIONS,
          recommended_action:  :map,
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "organization",
          serializer:          GitHub::Migrator::OrganizationSerializer,
          importer:            GitHub::Migrator::OrganizationImporter,
          mapping_actions:     [:map, :rename, :conflict],
          recommended_action:  :map,
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "repository",
          serializer:          GitHub::Migrator::RepositorySerializer,
          archiver:            GitHub::Migrator::RepositoryArchiver,
          importer:            GitHub::Migrator::RepositoryImporter,
          post_processor:      GitHub::Migrator::RepositoryPostProcessor,
          mapping_actions:     [:map, :rename],
          recommended_action:  :rename,
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "repository_advisory",
          serializer:          GitHub::Migrator::RepositoryAdvisorySerializer,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "team",
          serializer:          GitHub::Migrator::TeamSerializer,
          importer:            GitHub::Migrator::TeamImporter,
          mapping_actions:     [:map, :merge],
          recommended_action:  :merge,
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "protected_branch",
          serializer:          GitHub::Migrator::ProtectedBranchSerializer,
          importer:            GitHub::Migrator::ProtectedBranchImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "milestone",
          serializer:          GitHub::Migrator::MilestoneSerializer,
          importer:            GitHub::Migrator::MilestoneImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "issue",
          serializer:          GitHub::Migrator::IssueSerializer,
          importer:            GitHub::Migrator::IssueImporter,
          post_processor:      GitHub::Migrator::IssuePostProcessor,
          mapping_actions:     [:map],
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "pull_request",
          serializer:          GitHub::Migrator::PullRequestSerializer,
          importer:            GitHub::Migrator::PullRequestImporter,
          post_processor:      GitHub::Migrator::PullRequestPostProcessor,
          mapping_actions:     [:map],
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "project",
          serializer:          GitHub::Migrator::ProjectSerializer,
          importer:            GitHub::Migrator::ProjectImporter,
          mapping_actions:     [:map, :rename, :merge, :conflict],
          recommended_action:  :merge,
          cache_url_lookups:   true,
        ),
        GitHub::Migrator::MigratableModel.new(
          "pull_request_review",
          serializer:          GitHub::Migrator::PullRequestReviewSerializer,
          importer:            GitHub::Migrator::PullRequestReviewImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "pull_request_review_thread",
          serializer:          GitHub::Migrator::ReviewThreadSerializer,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "pull_request_review_comment",
          serializer:          GitHub::Migrator::ReviewCommentSerializer,
          importer:            GitHub::Migrator::ReviewCommentImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "commit_comment",
          serializer:          GitHub::Migrator::CommitCommentSerializer,
          importer:            GitHub::Migrator::CommitCommentImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "issue_comment",
          serializer:          GitHub::Migrator::IssueCommentSerializer,
          importer:            GitHub::Migrator::IssueCommentImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "issue_event",
          serializer:          GitHub::Migrator::IssueEventSerializer,
          importer:            GitHub::Migrator::IssueEventImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "attachment",
          serializer:          GitHub::Migrator::AttachmentSerializer,
          archiver:            GitHub::Migrator::AttachmentArchiver,
          importer:            GitHub::Migrator::AttachmentImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "release",
          serializer:          GitHub::Migrator::ReleaseSerializer,
          archiver:            GitHub::Migrator::ReleaseArchiver,
          importer:            GitHub::Migrator::ReleaseImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "repository_file",
          serializer:          GitHub::Migrator::RepositoryFileSerializer,
          archiver:            GitHub::Migrator::RepositoryFileArchiver,
          importer:            GitHub::Migrator::RepositoryFileImporter,
          mapping_actions:     [:map],
          cache_url_lookups:   false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "discussion",
          serializer:         GitHub::Migrator::DiscussionSerializer,
          mapping_actions:    [:map],
          cache_url_lookups:  false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "discussion_category",
          serializer:             GitHub::Migrator::DiscussionCategorySerializer,
          mapping_actions:        [:map],
          cache_url_lookups:      false,
        ),
        GitHub::Migrator::MigratableModel.new(
          "discussion_comment",
          serializer:            GitHub::Migrator::DiscussionCommentSerializer,
          mapping_actions:       [:map],
          cache_url_lookups:     false,
        )
      ]

      # Public: Array of model names for models that should have source_url to
      # target_url lookups cached.
      #
      # Returns an Array.
      def self.cache_url_lookup_models
        MIGRATABLE_MODELS.select { |mm| mm.cache_url_lookups }.map(&:model_type)
      end
    end
  end
end
