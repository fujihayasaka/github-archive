# typed: strict
# frozen_string_literal: true

class MemexProjectItem::ConvertToIssue

  ON_DRAFT_ISSUE_CONVERT_INSTRUMENTATION_KEY = "draft_issue.convert_to_issue"

  class Error < StandardError; end
  class NotSavedError < Error; end
  class RateLimitedError < Error; end
  class ValidationError < Error; end

  class AssetTransferResult < T::Struct
    const :new_body, String, default: ""
    const :body_changed, T::Boolean, default: false
  end

  class Warnings

    sig { returns(T.nilable(T::Array[String])) }
    attr_accessor :invalid_assignee_logins

    sig { returns(T.nilable(T::Hash[Symbol, T::Array[String]])) }
    def to_hash
      return nil unless invalid_assignee_logins.present?
      {
        invalidAssigneeLogins: invalid_assignee_logins
      }
    end
  end

  # Public: Convert the underlying draft issue for this item into a draft issue.
  #
  # This will update the content inline, and clean up the original draft issue
  # upon completion.
  #
  # This is a multi-step process, and uses a transaction to ensure the database
  # changes are rolled back if any step is unsuccessful.
  #
  # This will also raise an exception if any of the following criteria are not
  # satisfied:
  #
  #  - the content is an issue or pull request
  #  - the repository provided does not have issues enabled
  #  - the actor does not have read access to the repository (to allow for
  #    creating issues)
  #
  # Returns hash of any warnings during draft issue conversion e.g. assignees dropped due to access restrictions on
  # the target repo.
  sig do
    params(
      memex_project_item: MemexProjectItem,
      actor: T.nilable(User),
      repository: Repository
    ).returns(T.nilable(Warnings))
  end
  def self.call(memex_project_item:, actor:, repository:)
    new(memex_project_item: memex_project_item, actor: actor, repository: repository).call
  end

  sig do
    params(
      memex_project_item: MemexProjectItem,
      actor: T.nilable(User),
      repository: Repository
    ).void
  end
  def initialize(memex_project_item:, actor:, repository:)
    @memex_project_item = memex_project_item
    @actor = actor
    @repository = repository
    @warnings = T.let(Warnings.new, MemexProjectItem::ConvertToIssue::Warnings)
  end

  sig { returns(T.nilable(Warnings)) }
  def call
    validate

    existing_draft_issue = T.cast(memex_project_item.content, DraftIssue)

    title = existing_draft_issue.title
    body = existing_draft_issue.body || ""
    if !body.empty?
      res = transfer_assets_to_repository(body)
      body = res.new_body if res.body_changed
    end

    valid_assignees, invalid_assignees = memex_project_item.partition_valid_assignees(existing_draft_issue.assignees, repository)
    warnings.invalid_assignee_logins = invalid_assignees.map(&:display_login) if invalid_assignees.any?

    create_issue_attrs = Issues::CreateIssueAttributes.new(repository:, title:, body:, assignees: valid_assignees)
    result = Issues.domain.create(create_issue_attrs, safe_actor, raise_on_failed_permission: false).and_then do |issue|
      replace_content(existing_draft_issue, issue)
    end

    case result
    when GH::Result::Error::NotSaved
      raise NotSavedError.new(result.message)
    when GH::Result::Error::Validation
      raise RateLimitedError.new if result.message&.include?("was submitted too quickly")
      raise ValidationError.new(result.message)
    when GH::Result::Error
      raise Error.new(result.message)
    end

    warnings
  end

  sig { params(existing_draft_issue: DraftIssue, issue: Issues::IIssue).returns(GH::Result[T.untyped]) }
  def replace_content(existing_draft_issue, issue)
    MemexProjectItem.transaction do
      content_was_replaced = memex_project_item.update(content: issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      unless content_was_replaced
        raise ActiveRecord::RecordNotSaved.new(memex_project_item.errors.full_messages.to_sentence)
      end
      existing_draft_issue.destroy!
    end

    instrument_convert_to_issue(existing_draft_issue, T.cast(issue, Issue))

    GH::Result::Ok.new(nil)
  rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotDestroyed => e
    T.cast(issue, Issue).destroy! # domain-isolation-query-violation:ignore:packages/issues (DELETE, SELECT)
    GH::Result::Error::NotSaved.new(e.message)
  rescue ActiveRecord::RecordInvalid => e
    GH::Result::Error::Validation.new(e.record)
  end

  sig { params(draft_issue: DraftIssue, issue: Issue).returns(T::Hash[Symbol, T.untyped]) }
  def hydro_payload(draft_issue, issue)
    {
      actor: safe_actor,
      draft_issue:,
      issue:,
      project: memex_project_item.memex_project,
      project_item: memex_project_item,
      request_context: GitHub.context.to_hash
    }
  end

  private

  sig { returns(MemexProjectItem) }
  attr_reader :memex_project_item

  sig { returns(T.nilable(User)) }
  attr_reader :actor

  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(Warnings) }
  attr_reader :warnings

  sig { void }
  def validate
    unless memex_project_item.can_convert_to_issue?
      source_type = memex_project_item.content.is_a?(Issue) ? "an issue" : "a pull request" # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      raise Error.new "Cannot convert #{source_type} into an issue"
    end

    raise Error.new "Issues are not enabled for this repository" unless repository.has_issues?
    raise Error.new "User does not have access to this repository" unless repository.readable_by?(actor)
  end

  sig { params(body: String).returns(AssetTransferResult) }
  def transfer_assets_to_repository(body)
    urls = Storage::UserAssetTransfer::DraftToRepositoryTransfer.extract_urls_from_text(body)
    return transfer_result(body, false) if urls.empty?

    translations = Storage::UserAssetTransfer::DraftToRepositoryTransfer.transfer_by_urls(repository, actor, urls)
    return transfer_result(body, false) if translations.empty?

    translations.each { |t| body = body.gsub(t.original, t.translation) }
    transfer_result(body, true)
  rescue ArgumentError => e
    transfer_result(body, false)
  end

  sig { params(new_body: String, body_changed: T::Boolean).returns(AssetTransferResult) }
  def transfer_result(new_body, body_changed)
    AssetTransferResult.new(new_body: new_body, body_changed: body_changed)
  end

  sig { params(draft_issue: DraftIssue, issue: Issue).void }
  private def instrument_convert_to_issue(draft_issue, issue)
    payload = hydro_payload(draft_issue, issue)
    GlobalInstrumenter.instrument(ON_DRAFT_ISSUE_CONVERT_INSTRUMENTATION_KEY, payload)
  end

  sig { returns(User) }
  private def safe_actor
    @actor ||= User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end
end
