# typed: strict
# frozen_string_literal: true

module Exporter
  # Service to provide ActiveRecord scopes for different model types during serialization.
  #
  # This service abstracts scope logic away from legacy serializer code, providing
  # the necessary preloads and filters for efficient batch serialization. It merges
  # any existing scope from the serializer with additional scopes needed for export.
  #
  # Only models with custom export-specific preloading needs are defined here.
  # All other models will use their serializer's base scope (or empty relation if nil).
  #
  # Usage:
  #   scope_service = Exporter::SerializerScope.new(serializer: serializer, model_type: "issue")
  #   scope = scope_service.scope
  #   issues = Issue.where(id: ids).merge(scope).to_a
  class SerializerScope
    sig { params(serializer: GitHub::Migrator::BaseSerializer, model_type: String).void }
    def initialize(serializer:, model_type:)
      @serializer = serializer
      @model_type = model_type
    end

    # Returns the merged scope for serialization, combining the serializer's existing
    # scope with export-specific scopes. If the base scope is nil, uses an empty hash.
    sig { returns(T.any(ActiveRecord::Relation, T::Hash[T.untyped, T.untyped])) }
    def scope
      base_scope = @serializer.scope || {}
      custom_scope = custom_preloads

      return base_scope unless custom_scope

      migratable_model = MigratableModelResolver.resolve(model_type)
      model_class = migratable_model.model_class
      custom_scope = model_class.preload(custom_preloads)

      # If base_scope is a haqqqsh (empty or not), return custom_scope since it's already a relation
      # Otherwise merge custqom_scope into base_scope
      base_scope.is_a?(Hash) ? custom_scope : base_scope.merge(custom_scope)
    end

    private

    sig { returns(String) }
    attr_reader :model_type

    # Returns custom preloads for models that need them.
    # Returns nil for models that should use their base scope as-is.
    sig { returns(T.nilable(T::Array[Symbol])) }
    def custom_preloads
      case model_type
      when "attachments"
        [:asset, :attachable, :attacher]
      when "discussion_comment"
        [:parent_comment, { reactions: [:user] }]
      when "discussion"
        [:repository, :user, :labels, :category, { reactions: [:user] }]
      when "issue_comment"
        [:user, :reactions, { issue: :pull_request }, { reactions: [:user] }]
      when "issue_event"
        [:actor, :commit_repository, { issue: :pull_request }, { referencing_issue: :pull_request }]
      when "issue"
        [[:repository, :user, :assignee, :assignees, :milestone, :labels, { reactions: [:user] }]]
      when "organization"
        [:profile, :business_membership, :business, :configuration_entries, :user_labels, :hooks]
      when "project"
        [
          :owner,
          :creator,
          {
            columns: [
              :project_workflows,
              { cards: [:creator] }, # Removed :content to avoid loading all issues/PRs at once, causing timeouts
              { project_workflows: [:creator, :last_updater, { actions: [:creator, :last_updater] }] }
            ]
          }
        ]
      when "pull_request_review"
        [:pull_request, :user, :reactions, reactions: [:user]]
      when "pull_request"
        [:base_user, :base_repository, :head_user, :head_repository]
      when "release"
        [:release_assets, :repository, :author, :reactions, release_assets: [:uploader], reactions: [:user]]
      when "repository"
        [:network, :owner, :labels, :projects, :public_keys, :configuration_entries, :repository_topics, :page]
      when "pull_request_review_comment"
        [:pull_request, :pull_request_review, :pull_request_review_thread, :user, :reactions, :in_reply_to, reactions: [:user]]
      else
        # No custom preloads - will use base scope from serializer
        nil
      end
    end
  end
end
