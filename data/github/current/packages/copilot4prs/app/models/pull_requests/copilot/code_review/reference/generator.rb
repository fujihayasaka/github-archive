# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview
  class Reference::Generator
    CodeReviewReference = T.type_alias do
      T::Hash[Symbol, T.untyped]
    end

    BASE_REFERENCE_ATTRIBUTES = T.let(
      {
        type: "github.coding_guideline",
        data: { type: "coding-guideline" },
      },
      T::Hash[Symbol, T.any(String, T::Hash[Symbol, String])],
    )
    # The IDs of copilot instructions are hardcoded for now at a value
    # that won't conflict with any coding guideline IDs.
    # The contents of the repository custom instructions is sent as
    # one additional coding guideline.
    # When coding guidelines is disabled, we can index from 0.
    COPILOT_REPO_INSTRUCTIONS_ID = 1000000
    COPILOT_ORG_INSTRUCTIONS_ID = 1000001
    COPILOT_INSTRUCTIONS_MD_BASE_ID = 1000002

    sig { params(pr_ref: T::Hash[T.untyped, T.untyped], repository: Repository).void }
    def initialize(pr_ref:, repository:)
      @pr_ref = pr_ref
      @repository = repository
    end

    sig do
      params(
        pr_ref: T::Hash[T.untyped, T.untyped],
        repository: Repository,
      ).returns(T::Array[CodeReviewReference])
    end
    def self.generate(pr_ref:, repository:)
      new(pr_ref:, repository:).generate
    end

    sig { returns(T::Array[CodeReviewReference]) }
    def generate
      [
        repo_instructions_md,
        repo_custom_instructions,
        organization_custom_instructions,
      ].flatten.compact
    end

    private

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :pr_ref

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T.nilable(CodeReviewReference)) }
    def repo_custom_instructions
      return unless repo_custom_instructions_enabled?
      repo_reference = Copilot::CustomInstructions.for_repository(repository)
      merge_reference(repo_reference, COPILOT_REPO_INSTRUCTIONS_ID)
    end

    sig { returns(T.nilable(T::Array[CodeReviewReference])) }
    def repo_instructions_md
      return unless @repository.feature_flag_enabled?(:ccr_repo_instructions_md, default: false)
      return unless repo_custom_instructions_enabled?
      repo_references = Copilot::CustomInstructions.repo_instructions_md(repository, @pr_ref)
      return if repo_references.nil?
      repo_references.map.with_index do |source, index|
        merge_reference(source, COPILOT_INSTRUCTIONS_MD_BASE_ID + index)
      end
    end

    sig { returns(T.nilable(CodeReviewReference)) }
    def organization_custom_instructions
      return unless @repository.feature_flag_enabled?(:ccr_support_org_instructions, default: false)
      return unless repository.organization_id.present?
      org_reference = Copilot::CustomInstructions.for_organization_by_id(repository.organization_id, repository.owner_display_login)
      merge_reference(org_reference, COPILOT_ORG_INSTRUCTIONS_ID)
    end

    def repo_custom_instructions_enabled?
      repo_custom_instructions_settings = PullRequests::Copilot::CodeReviewRepositorySettings
      .find_by(repository: @repository)
      # By default, custom instructions is enabled for repositories
      # but the database value is nil until the user changes the state.
      repo_custom_instructions_settings&.repo_custom_instructions_enabled != false
    end

    def merge_reference(reference, id)
      return if reference.nil?
      BASE_REFERENCE_ATTRIBUTES.deep_merge(
        id: "#{@repository.name_with_display_owner}-#{id}",
        data: {
          id:,
          repositoryId: @repository.id,
          name: reference[:name],
          description: reference[:prompt],
          filePatterns: reference[:apply_to] || [],
        }
      )
    end
  end
end
