# typed: strict
# frozen_string_literal: true

module Copilot
  class CodingGuideline < ApplicationRecord::Copilot
    MAX_PER_REPO = 30
    MAX_ENABLED_PER_REPO = 6
    PROMPT_CHAR_LIMIT = 600

    self.table_name = "copilot_coding_guidelines"
    self.strict_loading_by_default = true

    include ::Repositories::BelongsToRepository
    flagged_belongs_to_repository_via_domain strict_loading: false
    has_many :paths,
      class_name: "Copilot::CodingGuidelinePath",
      strict_loading: false,
      foreign_key: :copilot_coding_guideline_id,
      inverse_of: :copilot_coding_guideline

    has_many :code_review_comments,
      class_name: "PullRequests::Copilot::CodeReviewComment",
      foreign_key: :copilot_coding_guideline_id,
      inverse_of: :copilot_coding_guideline

    accepts_nested_attributes_for :paths, allow_destroy: true, reject_if: :all_blank

    validates :name, presence: true, length: { maximum: 200 }, uniqueness: { scope: :repository_id }
    validates :description, presence: true, length: { maximum: PROMPT_CHAR_LIMIT }
    validates :example_code_violations, length: { maximum: PROMPT_CHAR_LIMIT }
    validate :validate_enabled_guidelines_limit, if: :enabled?
    validate :validate_total_guidelines_limit, on: :create

    before_validation :set_default_enabled_status, on: :create

    sig { params(repository_id: T.nilable(Integer)).returns(T::Array[T::Hash[T.untyped, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
    def self.references_for(repository_id)
      repo = Repository.find_by(id: repository_id)
      return [] unless repo

      self.where(repository: repo, enabled: true).includes(:repository)
        .limit(Copilot::CodingGuideline::MAX_ENABLED_PER_REPO)
        .map(&:to_copilot_reference)
    end

    # This method is used to serialize the paths for the guideline React form
    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) } # rubocop:disable Sor, Sorbet/ForbidTUntyped
    def paths_attributes
      return [] unless persisted?
      paths.map { |path| { id: path.id, path: path.path, markedForDestroy: false } }
    end

    # This method serializes the coding guideline into a Copilot reference.
    # The `exclude_file_patterns` flag determines whether to include file path matchers.
    # If `exclude_file_patterns` is true, file path matchers are excluded from the reference.
    # This is useful for evaluations in the playground to ensure Copilot reviews raw code
    # without filtering based on file patterns, as the code is not associated with real file paths.
    sig { params(exclude_file_patterns: T.nilable(T::Boolean)).returns(T::Hash[T.untyped, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def to_copilot_reference(exclude_file_patterns: false)
      repo = T.must(repository)

      {
        type: "github.coding_guideline",
        id: "#{repo.name_with_display_owner}-#{id}",
        data: {
          id: id,
          type: "coding-guideline",
          repositoryId: repo.id,
          name: name,
          description: description,
          filePatterns: exclude_file_patterns ? [] : paths.map { |path| path.path }
        }
      }
    end

    private

    sig { void }
    def set_default_enabled_status
      return unless repository

      if repository_enabled_limit_exceeded?
        self.enabled = false
      else
        self.enabled = true
      end
    end

    sig { void }
    def validate_enabled_guidelines_limit
      return unless repository

      existing_count = self.class
        .where(repository: repository, enabled: true)
        .where.not(id: id)
        .count

      return if existing_count < MAX_ENABLED_PER_REPO

      errors.add(:enabled, "cannot be enabled because the repository has reached the limit of #{MAX_ENABLED_PER_REPO} enabled guidelines")
    end

    sig { void }
    def validate_total_guidelines_limit
      return unless repository

      existing_count = self.class
        .where(repository: repository)
        .count

      return if existing_count < MAX_PER_REPO

      errors.add(:base, "cannot create more than #{MAX_PER_REPO} guidelines for a repository")
    end

    sig { returns(T::Boolean) }
    def repository_enabled_limit_exceeded?
      self.class.where(repository: repository, enabled: true).count >= MAX_ENABLED_PER_REPO
    end
  end
end
