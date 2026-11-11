# typed: strict
# frozen_string_literal: true

# INTERNAL ONLY: Helper module for sub-issue reprioritization logic shared between
# the REST API (Api::SubIssues), Memex controller (Memexes::ItemsController),
# and GraphQL mutations (Mutations::ReprioritizeSubIssue)
#
# This helper performs upfront validation to ensure:
# - Exactly one positioning argument is provided (before_issue, after_issue, or top)
# - The sub-issue is a valid child of the specified parent issue
# - Any positional reference issue (before/after) is also a valid child of the same parent
module SubIssueReprioritizationHelper
  # Result object for reprioritization operations
  class Result < T::Struct
    const :success, T::Boolean
    const :error_message, T.nilable(String)
    const :error_status, T.nilable(Symbol)
    const :prioritization_args, T.nilable(T::Hash[Symbol, T.untyped])
    const :sub_issue_relation, T.nilable(SubIssue)

    sig { returns(T::Boolean) }
    def success?
      success
    end

    sig do
      params(
        prioritization_args: T::Hash[Symbol, T.untyped],
        sub_issue_relation: SubIssue
      ).returns(Result)
    end
    def self.success(prioritization_args:, sub_issue_relation:)
      new(success: true, prioritization_args: prioritization_args, sub_issue_relation: sub_issue_relation)
    end

    sig do
      params(
        message: String,
        status: Symbol
      ).returns(Result)
    end
    def self.error(message:, status:)
      new(success: false, error_message: message, error_status: status)
    end
  end

  # Validates and builds reprioritization arguments for a sub-issue
  #
  # @param parent_issue [Issue] The parent issue
  # @param sub_issue [Issue] The sub-issue being reprioritized
  # @param before_issue [Issue, nil] The issue to place before
  # @param after_issue [Issue, nil] The issue to place after
  # @param top [Boolean, nil] Whether to move the sub-issue to the top
  # @return [Result] A result object indicating success or failure
  sig do
    params(
      parent_issue: Issue,
      sub_issue: Issue,
      before_issue: T.nilable(Issue),
      after_issue: T.nilable(Issue),
      top: T.nilable(T::Boolean)
    ).returns(Result)
  end
  def self.build_reprioritization_args(parent_issue:, sub_issue:, before_issue: nil, after_issue: nil, top: nil)
    # Validate that at least one positioning argument is provided
    unless before_issue.present? || after_issue.present? || top
      return Result.error(
        message: "Either a before_issue or after_issue or top argument must be provided.",
        status: :unprocessable_entity
      )
    end

    # Validate that only one positioning argument is provided
    positioning_args_count = [before_issue.present?, after_issue.present?, top].count(true)
    if positioning_args_count > 1
      return Result.error(
        message: "Only one of the before_issue, after_issue, or top argument may be provided, but not multiple.",
        status: :unprocessable_entity
      )
    end

    # Validate that the sub-issue is actually a sub-issue of the parent
    sub_issue_relation = sub_issue.parent_issue_relation
    unless sub_issue_relation.present? && sub_issue_relation.source_issue_id == parent_issue.id
      return Result.error(
        message: "Provided sub-issue is not a sub-issue of the provided parent.",
        status: :unprocessable_entity
      )
    end

    # Build prioritization arguments
    prioritization_args = if top
      { position: :top }
    elsif before_issue.present?
      result = build_positional_arg(parent_issue: parent_issue, positional_issue: before_issue, position: :before)
      return result unless result.success?
      T.must(result.prioritization_args)
    else
      result = build_positional_arg(parent_issue: parent_issue, positional_issue: T.must(after_issue), position: :after)
      return result unless result.success?
      T.must(result.prioritization_args)
    end

    Result.success(prioritization_args: prioritization_args, sub_issue_relation: sub_issue_relation)
  end

  # Builds the positional argument hash for reprioritization
  #
  # @param parent_issue [Issue] The parent issue
  # @param positional_issue [Issue] The positional issue (before/after reference)
  # @param position [Symbol] Either :before or :after
  # @return [Result] A result object with the prioritization args or an error
  sig do
    params(
      parent_issue: Issue,
      positional_issue: Issue,
      position: Symbol
    ).returns(Result)
  end
  def self.build_positional_arg(parent_issue:, positional_issue:, position:)
    positional_relation = positional_issue.parent_issue_relation

    unless positional_relation.present? && positional_relation.source_issue_id == parent_issue.id
      return Result.error(
        message: "Provided positional argument is not a sub-issue of the provided parent.",
        status: :unprocessable_entity
      )
    end

    # Create a placeholder Result for the intermediate return - sub_issue_relation will be set at the final call site
    Result.new(
      success: true,
      prioritization_args: { position => positional_relation },
      sub_issue_relation: nil
    )
  end
end
