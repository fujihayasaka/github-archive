# typed: strict
# frozen_string_literal: true

class MemexProjectItem::ConvertToIssue

  ON_DRAFT_ISSUE_CONVERT_INSTRUMENTATION_KEY = "draft_issue.convert_to_issue"

  class Error < StandardError; end

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
    ).returns(Warnings)
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

  sig { returns(Warnings) }
  def call
    validate

    existing_draft_issue = memex_project_item.content

    builder_params = {}
    builder_params[:issue] = { title: existing_draft_issue.title }
    builder_params[:issue][:body] = existing_draft_issue.body

    body = builder_params[:issue][:body] || ""
    if !body.empty?
      res = transfer_assets_to_repository(body)
      builder_params[:issue][:body] = res.new_body if res.body_changed
    end

    invalid_logins = memex_project_item.build_assignee_params(existing_draft_issue.assignees, builder_params,
      repository)
    warnings.invalid_assignee_logins = invalid_logins if invalid_logins.any?

    issue_builder = Issue::Builder.new(actor, repository)
    issue = issue_builder.build(builder_params)
    issue.save!

    begin
      MemexProjectItem.transaction do
        content_was_replaced = memex_project_item.replace_content(issue, actor)
        unless content_was_replaced
          raise ActiveRecord::RecordNotSaved.new(memex_project_item.errors.full_messages.to_sentence)
        end
        existing_draft_issue.destroy!
      end
     rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotDestroyed => exception
       issue.destroy!
       raise exception
    end

    instrument_convert_to_issue(existing_draft_issue, issue)

    warnings
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
      source_type = memex_project_item.content.is_a?(Issue) ? "an issue" : "a pull request"
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
