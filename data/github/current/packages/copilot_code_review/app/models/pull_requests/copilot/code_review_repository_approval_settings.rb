# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodeReviewRepositoryApprovalSettings < ApplicationRecord::Domain::Copilot
      MAX_FILE_PATTERN_COUNT = 15
      QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_ALL_FILES = T.let("all_files", String)
      QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_FILE_PATTERNS = T.let("file_patterns", String)
      QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_VALUES = T.let(
        [
          QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_ALL_FILES,
          QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_FILE_PATTERNS,
        ].freeze,
        T::Array[String],
      )

      self.table_name = "copilot_code_review_repository_approval_settings"
      self.strict_loading_by_default = true

      include ::Repositories::BelongsToRepository
      belongs_to_repository_via_domain

      validates :repository, uniqueness: true
      validates :repo_qualified_approval_scope_when_enabled, inclusion: { in: QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_VALUES }
      validate :validate_qualified_approval_file_patterns

      sig { params(repository: ::Repository).returns(T::Boolean) }
      def self.has_auto_approve_when_delegated?(repository:)
        exists?(repository: repository, repo_auto_approve_when_delegated: true)
      end

      sig { params(repository: ::Repository).returns(T::Boolean) }
      def self.has_qualified_approval_when_delegated?(repository:)
        exists?(repository: repository, repo_qualified_approval_when_delegated: true)
      end

      sig { returns(Symbol) }
      def qualified_approval_scope_when_enabled
        normalized_qualified_approval_scope_when_enabled.to_sym
      end

      sig { returns(T::Boolean) }
      def qualified_approval_scope_when_enabled_all_files?
        qualified_approval_scope_when_enabled == :all_files
      end

      sig { returns(T::Boolean) }
      def qualified_approval_scope_when_enabled_file_patterns?
        qualified_approval_scope_when_enabled == :file_patterns
      end

      sig { returns(T::Boolean) }
      def qualified_approval_when_delegated?
        T.cast(self[:repo_qualified_approval_when_delegated], T::Boolean)
      end

      sig { returns(T::Boolean) }
      def auto_approve_when_delegated?
        T.cast(self[:repo_auto_approve_when_delegated], T::Boolean)
      end

      sig { returns(T::Array[String]) }
      def qualified_approval_file_patterns
        repo_qualified_approval_file_patterns_value.to_s.lines.map(&:strip).reject(&:blank?)
      end

      sig { returns(String) }
      def qualified_approval_file_patterns_text
        repo_qualified_approval_file_patterns_value.to_s
      end

      sig { params(scope_when_enabled: T.any(String, Symbol), file_patterns_text: String).void }
      def assign_qualified_approval_scope_when_enabled(scope_when_enabled:, file_patterns_text:)
        normalized_scope_when_enabled = scope_when_enabled.to_s
        self[:repo_qualified_approval_scope_when_enabled] = normalized_scope_when_enabled
        self[:repo_qualified_approval_file_patterns] = nil if normalized_scope_when_enabled == QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_ALL_FILES
        return unless normalized_scope_when_enabled == QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_FILE_PATTERNS

        self[:repo_qualified_approval_file_patterns] = file_patterns_text.to_s
      end

      private

      sig { returns(String) }
      def normalized_qualified_approval_scope_when_enabled
        scope_when_enabled = repo_qualified_approval_scope_when_enabled_value
        return QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_ALL_FILES if scope_when_enabled.nil?
        return QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_ALL_FILES unless QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_VALUES.include?(scope_when_enabled)

        scope_when_enabled
      end

      sig { returns(T.nilable(String)) }
      def repo_qualified_approval_file_patterns_value
        T.cast(self[:repo_qualified_approval_file_patterns], T.nilable(String))
      end

      sig { returns(T.nilable(String)) }
      def repo_qualified_approval_scope_when_enabled_value
        T.cast(self[:repo_qualified_approval_scope_when_enabled], T.nilable(String))
      end

      sig { void }
      def validate_qualified_approval_file_patterns
        return unless qualified_approval_scope_when_enabled_file_patterns?

        if qualified_approval_file_patterns.size > MAX_FILE_PATTERN_COUNT
          errors.add(:repo_qualified_approval_file_patterns, "exceeded limit of #{MAX_FILE_PATTERN_COUNT} file patterns")
        end
      end
    end
  end
end
