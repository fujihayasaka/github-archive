# typed: true
# frozen_string_literal: true

class IssueTransfer < ApplicationRecord::Collab
  DEFAULT_TRANSFER_TRAVERSAL_DEPTH = 10

  STATES = %w[started done errored]
  REASONS = %w[
    Misfiled
    Sensitive
    Reorganization
    Other
  ]

  ISSUE_EVENT_BLOCKLIST = %w[
    added_to_project
    moved_columns_in_project
    removed_from_project
    converted_note_to_issue
    converted_to_discussion
    project_v2_item_status_changed
    converted_from_draft
    added_to_project_v2
    removed_from_project_v2
  ]

  LABEL_EVENTS = %w[
    labeled
    unlabeled
  ]

  MILESTONE_EVENTS = %w[
    milestoned
    demilestoned
  ]

  SUB_ISSUE_BATCH_TRANSFER_SIZE = 50

  SUB_ISSUE_MAX_REPLICATION_WAIT_TIME = 5

  belongs_to :old_repository, class_name: "Repository", required: true
  belongs_to :old_issue, class_name: "Issue", required: true

  belongs_to :new_repository, class_name: "Repository", required: true
  belongs_to :new_issue, class_name: "Issue", required: true

  belongs_to :actor, class_name: "User"

  before_validation :set_initial_state, on: :create
  before_validation :set_old_issue_number, on: :create

  validates :old_issue_number, presence: true
  validates :state, presence: true, inclusion: { in: STATES }
  validates :reason, inclusion: { in: REASONS, allow_nil: true }
  validate :old_issue_unlocked
  validate :actor_permissions
  validate :repos_not_archived
  validate :repos_have_issues
  validate :transferrable_by_actor
  validate :with_same_owner
  validate :not_transferring_private_to_public

  def self.find_from(repository:, number:)
    first_transfer = find_by(old_repository_id: repository.id, old_issue_number: number)
    if first_transfer
      return unravel_transfer_chain(first_transfer: first_transfer)
    end
    nil
  end

  def self.find_new_id_by_original_id(original_id:)
    first_transfer = find_by(old_issue_id: original_id)
    if first_transfer
      return unravel_transfer_chain(first_transfer: first_transfer)&.new_issue_id
    end
    nil
  end

  def self.unravel_transfer_chain(first_transfer:)
    DEFAULT_TRANSFER_TRAVERSAL_DEPTH.times.inject(first_transfer) do |transfer|
      # Is this the final transfer? Return the id!
      return transfer if transfer.new_issue

      # Can we find a new issue transfer? If not, bail out
      return unless next_transfer = find_by(old_issue_id: transfer.new_issue_id)

      next_transfer
    end
    nil
  end

  def async_transfer!(create_labels_if_missing: false)
    create_copy_issue unless new_issue

    options = {
      create_labels_if_missing: create_labels_if_missing
    }

    TransferIssueJob.perform_later(self, options)
  end

  def transfer!(staff_user: nil, create_labels_if_missing: false)
    create_copy_issue unless new_issue
    complete_transfer(staff_user: staff_user, create_labels_if_missing: create_labels_if_missing)
  end

  def complete_transfer(staff_user: nil, create_labels_if_missing: false)
    return unless old_issue = self.old_issue

    new_issue = T.must(self.new_issue)
    audit_log_user = (staff_user.present? && staff_user.site_admin?) ? staff_user : actor

    begin
      old_issue.transfer = true
      new_issue.transfer = true

      # NOTE: transferring subs must come first so please don't change the ordering :)
      transfer_subscribers
      transfer_assignments
      transfer_issue_type
      transfer_events_and_labels(create_labels_if_missing: create_labels_if_missing)
      transfer_edits

      transfer_issue_comments
      copy_reactions(old_issue, new_issue)
      transfer_close_issue_references

      # needs to execute after transferring comments.
      copy_references

      # For Issues that belong to Projects, update any of their cards
      transfer_legacy_project_cards

      # For Issues that belong to Memex Projects, update any of their items
      transfer_memex_project_items

      # NOTE: We do not validate that new repo has sub-issues.
      # The issue will be transfered to a repo with the same owner, so it is likely the new repo has sub-issues.
      # There is a possibility that the target repo does not have sub-issues enabled,
      # however we want to create the sub-issues regardless to avoid possible data loss.

      # For Issues have sub-issues, transfer them
      transfer_sub_issues

      # For Issues have a parent issue, update parent references
      transfer_parent_reference

      # Issue transferring is kept last to minimize the time an issue could have non-visible images/videos
      # for a user who has no permissions to view the destination repo
      # For more info, review this decision in https://github.com/github/issues/issues/11041#issuecomment-2283723818
      transfer_issue_assets

      # TODO: Comment why this is here
      new_issue.synchronize_search_index

      # Show an event on the new issue
      IssueEvent.throttle_with_retry { new_issue.events.create!(actor: actor, event: "transferred", subject: old_repository) }

      # Keep the original created_at (can be removed once all in progress transfers have completed)
      new_issue.throttle_with_retry { new_issue.update_column(:created_at, old_issue.created_at) } unless new_issue.created_at == old_issue.created_at
      # Trigger event for audit log of the old org (to signal that issue is moving out)
      old_issue.instrument(:transfer,
                           actor: audit_log_user,
                           issue_transfer: self)

      # Instrument for Hydro
      GlobalInstrumenter.instrument(
        "issue.transferred",
        actor: actor,
        old_issue: old_issue,
        new_issue: new_issue,
        old_repository: old_repository,
        new_repository: new_repository,
      )

      # Set deletion_hook_action to signify this is a transfer event
      old_issue.deletion_hook_action = :transferred

      # Get rid of the old one and sends deletion webhook
      Issue.throttle_with_retry { old_issue.destroy }

      clean_up_old_issue

      self.throttle_with_retry { update_attribute(:state, "done") }

      T.must(new_issue).notify_transfer_state_updated
    rescue => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e)
      update_attribute(:state, "errored")

      raise e
    end

    nil
  end

  def transfer_edits
    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    transfer_key = -> (record) { [record.editor_id, record.created_at, record.compressed_diff] }
    new_edits = new_issue.user_content_edits.map { |record| transfer_key.call(record) }
    new_records = old_issue.user_content_edits.filter_map do |record|
      next if new_edits.include? transfer_key.call(record)
      record.attributes
        .slice(*IssueEdit.column_names)
        .symbolize_keys
        .except(:id, :user_content_edit_id)
        .merge(
          issue_id: new_issue.id,
          repository_id: T.must(new_repository).id
        )
    end
    IssueEdit.throttle_with_retry { IssueEdit.create!(new_records) } unless new_records.empty?
  end

  def clean_up_old_issue
    old_issue = T.must(self.old_issue)
    old_assignment_ids = old_issue.assignments.pluck(:id)
    assignments = Assignment.where(id: old_assignment_ids)
    assignments.each { |a| a.throttle_with_retry { a.destroy } }
  end

  # This is triggered from stafftools for issue transfers that have been stuck
  def retry_transfer
    new_issue = T.must(self.new_issue)

    begin
      Rails.logger.info "Retrying to transfer issue #{self.old_issue_id} starting."

      new_issue.synchronize_search_index

      # Show an event on the new issue
      IssueEvent.throttle_with_retry { new_issue.events.create!(actor: actor, event: "transferred", subject: old_repository) }

      self.throttle_with_retry { update_attribute(:state, "done") }
      Rails.logger.info "Retrying to transfer issue #{self.old_issue_id} to #{self.new_issue_id} finished."
      rescue => e # rubocop:todo Lint/GenericRescue
        Rails.logger.info "Retrying to transfer issue #{self.old_issue_id} to #{self.new_issue_id} failed."
        Failbot.report(e)
        update_attribute(:state, "errored")
        unless Rails.env.production?
          raise e
        end
    end
  end

  def create_copy_issue
    self.new_issue = create_empty_copy_issue

    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    # This is here to fix a potential circular reference if the issue references itself, therefore `new_issue` is required to exist first.
    new_issue.body = replace_body_mentions(old_issue.body.dup)
    # Disabling rate limit as we're saving new issue twice in a row - might hit rate limit
    # See https://janky.githubapp.com/flaky_tests/5e01b9083c036a01da68ad44851da679990fa44c559258d23ce0ab6c92d58a9e
    GitHub::RateLimitedCreation.disable_content_creation_rate_limits { new_issue.save! }

    save!
  end

  def create_empty_copy_issue
    old_issue = T.must(self.old_issue)

    self.new_issue = Issue.create!(
        repository: new_repository,
        user_id: old_issue.safe_user.id,
        title: old_issue.title,
        body: nil,
        issue_comments_count: old_issue.issue_comments_count,
        state: old_issue.state,
        user_hidden: old_issue.user_hidden,
        performed_by_integration_id: old_issue.performed_by_integration_id,
        transfer: true,
        closed_at: old_issue.closed_at,
        created_at: old_issue.created_at,
        state_reason: old_issue.state_reason,
      )
  end

  def replace_body_mentions(body, source_issue_repo_id: nil, target_issue: nil)
    replace_reference_mentions(replace_bare_issue_mentions(body, source_issue_repo_id, target_issue))
  end

  private

  # Transfers issue and comment images and videos to the new repository
  sig { void }
  def transfer_issue_assets
    new_issue = T.must(self.new_issue)
    return if new_issue.repository.nil?
    target_repo = T.must(new_issue.repository)

    old_issue = T.must(self.old_issue)
    return if old_issue.repository.nil?
    origin_repo = T.must(old_issue.repository)
    return if old_issue.body.nil?

    transfer_assets(origin_repo, target_repo, old_issue, new_issue)

    old_issue.comments.each do |comment|
      next if comment.body.nil?

      transfer_assets(origin_repo, target_repo, comment)
    end
  end

  # Parses asset from issue/comment body, transfers issue to target_repo and updates the issue/comment body with the new asset URLs
  # @param origin_repo [Repository] - the repository to transfer the assets from
  # @param target_repo [Repository] - the repository to transfer the assets to
  # @param origin [Issue|IssueComment] - the issue or comment to extract the url from
  # @param target [Issue|IssueComment] (optional) - the issue or comment to update the body with the new asset URLs, defaults to origin
  sig { params(origin_repo: Repository, target_repo: Repository, origin: T.any(Issue, IssueComment), target: T.nilable(T.any(Issue, IssueComment))).void }
  def transfer_assets(origin_repo, target_repo, origin, target = nil)
    target = origin if target.nil?
    body = origin.body

    urls = Storage::UserAssetTransfer::RepositoryToRepositoryTransfer.extract_urls_from_text(body)
    return if urls.length == 0

    has_transferred_assets = T.let(false, T::Boolean)
    # Individually transferring each asset to gracefully ignore any assets the user doesn't have access to
    urls.each do |url|
      begin
        url_translations = Storage::UserAssetTransfer::RepositoryToRepositoryTransfer.transfer_by_urls(origin_repo, target_repo, actor, [url])
        next if url_translations.length == 0

        has_transferred_assets = true
        url_translations.each do |asset|
          body.gsub!(asset.original, asset.translation)
        end
      rescue Storage::UserAssetTransfer::Transfer::TransferError => e
        is_comment = origin.is_a?(IssueComment)
        comment = is_comment ? origin : nil

        message = "Could not transfer issue #{is_comment ? "comment" : "body"} assets"

        GitHub.logger.error(
          "#{message}#transfer_issue_assets",
          {
            :exception => e,
            "gh.repo.id" => self.old_repository_id,
            "gh.issue.id" => self.old_issue_id,
            "gh.comment.id" => is_comment ? comment.id : nil,
            "gh.new_repo.id" => self.new_repository_id,
            "gh.actor.id" => self.actor_id,
            "gh.asset_url" => url
          }
        )
      end
    end

    return unless has_transferred_assets

    target.body = body
    target.save!
  end

  def transfer_issue_type
    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    return unless old_issue.issue_type.present?

    begin
      new_issue.update!(issue_type: old_issue.issue_type)
    rescue ActiveRecord::RecordInvalid
      new_issue.reload
    end
  end

  def transfer_assignments
    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    assignment_key = -> (a) { [a.assignee, a.created_at] }
    existing_assignments = new_issue.assignments.map { |a| assignment_key.call(a) }
    old_issue.assignments.
      reject { |a| existing_assignments.include?(assignment_key.call(a)) }.
      each do |assignment|
      assignment.throttle_with_retry do
        Assignment.create!(
          assignee: assignment.assignee,
          issue: new_issue,
          repository_id: T.must(new_issue.repository).id,
          created_at: assignment.created_at,
          skip_ensure_assignee_is_a_collaborator: true,
          skip_trigger_assigned_event: true)
      end
    end
  end

  def transfer_labels(old_to_new_label_mapping, create_labels_if_missing: false)
    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    new_labels = old_issue.labels.map do |label|
      target_label = old_to_new_label_mapping[label.id]
      if target_label.present?
        target_label
      elsif create_labels_if_missing
        label.throttle_with_retry { T.must(new_issue.repository).labels.create!(name: label.name, lowercase_name: label.lowercase_name, color: label.color, created_at: label.created_at) }
      else
        nil
      end
    end

    new_issue.labels << new_labels.compact.difference(T.unsafe(new_issue).labels) # difference to avoid adding existing labels.
  end

  def transfer_milestone(milestones_in_target_repo)
    old_issue = T.must(self.old_issue)

    if old_issue.milestone.present?
      new_issue = T.must(self.new_issue)
      milestone = find_milestone_in_new_repo(T.must(old_issue.milestone).title, T.must(old_issue.milestone).due_on, milestones_in_target_repo)
      # only transfer a milestone that exists in the target repo (title and due date both match)
      if milestone.present?
        new_issue.milestone = milestone
        new_issue.throttle_with_retry { new_issue.save! }
      end
    end
  end

  # this is mainly used for eliminating redundant DB queries for the same milestones
  def find_milestone_in_new_repo(title, due_date, milestones_in_target_repo)
    return unless new_issue = self.new_issue
    return milestones_in_target_repo[[title, due_date]] if milestones_in_target_repo.has_key?([title, due_date])

    milestones_in_target_repo[[title, due_date]] = if T.must(new_issue.repository).milestones.present?
      milestone = T.must(new_issue.repository).milestones.find_by(title: title, due_on: due_date)
    else
      nil
    end
  end

  def transfer_events_and_labels(create_labels_if_missing: false)
    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    preload_events_and_details

    old_to_new_label_mapping = get_label_mapping
    transfer_labels(old_to_new_label_mapping, create_labels_if_missing: create_labels_if_missing)

    # update labels with newly transferred ones
    old_to_new_label_mapping = get_label_mapping

    milestones_in_target_repo = Hash.new
    transfer_milestone(milestones_in_target_repo)
    old_milestone_mapping = get_old_milestone_mapping

    new_events = new_issue.events

    old_issue.events.each do |old_event|
      next if ISSUE_EVENT_BLOCKLIST.include?(old_event.event)
      next unless old_event.issue_event_detail&.id
      next if old_event.actor.nil?

      # Skip any label or milestone events that aren't present in the target repositories
      if MILESTONE_EVENTS.include?(old_event.event)
        milestone = find_milestone_in_new_repo(old_event.issue_event_detail.milestone_title, old_milestone_mapping[old_event.issue_event_detail.milestone_id], milestones_in_target_repo)
        next unless milestone.present?
      end

      if LABEL_EVENTS.include?(old_event.event) && !create_labels_if_missing
        next unless old_to_new_label_mapping[old_event.issue_event_detail.label_id]
      end

      new_event = new_events.find do |e|
        e.actor_id == old_event.actor_id &&
        e.created_at == old_event.created_at &&
        e.event == old_event.event
      end

      new_event = copy_event(old_event, old_to_new_label_mapping, old_milestone_mapping, milestones_in_target_repo) if new_event.nil?
      copy_event_detail(old_event, new_event)
    end
  end

  def copy_event(old_event, old_to_new_label_mapping, old_milestone_mapping, milestones_in_target_repo)
    attrs = {
      # ignoring `raw_data` here, relying on the fact that its properties were already serialized
      # into issue_event_detail in the source issue
      **old_event.attributes.slice(*IssueEvent.column_names).except("id", "repository_id", "raw_data", "issue_id"),
      issue_id: T.must(new_issue).id,
      issue_transfer: true,
    }

    if LABEL_EVENTS.include?(old_event.event) &&
        old_event.issue_event_detail.label_name.present?
      label = old_to_new_label_mapping[old_event.issue_event_detail.label_id]
      attrs[:label] = label if label
    end

    if MILESTONE_EVENTS.include?(old_event.event) &&
        old_event.issue_event_detail.milestone_id.present? &&
        old_event.issue_event_detail.milestone_title.present?
      milestone = find_milestone_in_new_repo(old_event.issue_event_detail.milestone_title, old_milestone_mapping[old_event.issue_event_detail.milestone_id], milestones_in_target_repo)
      if milestone.present?
        attrs[:milestone_id] = milestone.id
        attrs[:milestone_title] = milestone.title
      end
    end

    IssueEvent.throttle_with_retry { IssueEvent.create!(attrs) }
  end

  def copy_event_detail(old_event, new_event)
    old_detail = old_event.issue_event_detail
    new_detail = new_event.issue_event_detail

    attrs = {
      **old_detail.attributes.slice(*IssueEventDetail.column_names).except("id", "issue_event_id", "label_id", "label_color", "label_text_color", "label_name", "repository_id", "milestone_id", "milestone_title"),
      issue_event_id: new_event.id,
      repository_id: T.must(new_issue).repository_id
    }

    new_detail.attributes = attrs
    IssueEventDetail.throttle_with_retry { new_detail.save }
  end

  def transfer_issue_comments
    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    ActiveRecord::Associations::Preloader.new(
      records: old_issue.comments + new_issue.comments,
      associations: [:reactions, :attachments, :user_content_edits],
      available_records: []
    ).call

    find_comment = -> (new_comments, old_comment) {
      new_comments.find do |new_comment|
        new_comment.user_id == old_comment.user_id &&
        new_comment.created_at == old_comment.created_at
      end
    }

    new_comments = new_issue.comments

    old_issue.comments.each do |old_comment|
      # Some flows, like import, can create invalid comments - for example comments with empty body.
      # Those will fail on being invalid when we'll try to copy them so we'll skip them.
      next if !old_comment.valid?

      new_comment = find_comment.call(new_comments, old_comment) || copy_comment(old_comment)
      # TODO: Should/Could all of the below be done in parallel with Promise.all or
      # similar?
      copy_comment_edits(old_comment, new_comment) unless old_comment.user_content_edits.empty?
      update_comment_attachments(old_comment, new_comment) unless old_comment.attachments.empty?
      copy_reactions(old_comment, new_comment)
      copy_comment_content_references(old_comment, new_comment)
    end
  end

  def copy_comment(comment)
    new_body = replace_body_mentions(comment.body.dup)
    attrs = comment.attributes.slice(*IssueComment.column_names)
      .symbolize_keys
      .except(:id, :body)
      .merge(
        issue_id: T.must(new_issue).id,
        repository_id: new_repository_id,
        compressed_body: new_body,
        issue_transfer: true
      )
    IssueComment.throttle_with_retry { IssueComment.create!(attrs) }
  end

  def copy_comment_edits(old_comment, new_comment)
    transfer_key = -> (record) { [record.editor_id, record.created_at, record.compressed_diff] }
    new_edits = new_comment.user_content_edits.map { |record| transfer_key.call(record) }
    new_records = old_comment.user_content_edits.filter_map do |record|
      next if new_edits.include? transfer_key.call(record)
      # We remove :user_content_edit_id because this column is no longer
      # relevant to IssueCommentEdit, but there is an old uniqueness index on it that
      # will throw exceptions when we try to create a new similar record for the
      # transferred comment. See # https://github.com/github/data-partitioning/issues/706.
      record.attributes
        .slice(*IssueCommentEdit.column_names)
        .symbolize_keys
        .except(:id, :user_content_edit_id)
        .merge(issue_comment_id: new_comment.id)
    end
    IssueCommentEdit.throttle_with_retry { IssueCommentEdit.create!(new_records) } unless new_records.empty?
  end

  def update_comment_attachments(old_comment, new_comment)
    return if new_comment.nil?
    Attachment.throttle_with_retry do
      old_comment.attachments.update_all(
        attachable_id: new_comment.id,
        entity_id: T.must(new_repository).id
      )
    end
  end

  def copy_reactions(old_record, new_record)
    return if old_record.reactions.empty?

    class_name = old_record.class.name
    class_name = old_record.class.name
    key_column = :issue_comment_id
    key_column = :issue_id if class_name == "Issue"

    transfer_key = -> (reaction) { [reaction.user_id, reaction.created_at, reaction.content] }

    new_reactions = new_record.reactions
    new_records = old_record.reactions.filter_map do |old_reaction|
      existing = new_reactions.find do |new_reaction|
        transfer_key.call(new_reaction) == transfer_key.call(old_reaction)
      end
      unless existing
        old_reaction.attributes
          .slice(*Reaction.column_names)
          .symbolize_keys
          .except(:id)
          .merge(
            subject_id: new_record.id,
            subject_type: class_name
          )
      end
    end

    unless new_records.empty?
      reactions = new_records.map do |record|
        hash = {
          content: record[:content],
          user_id: record[:user_id],
          user_hidden: record[:user_hidden],
          created_at: record[:created_at],
          updated_at: record[:updated_at],
          repository_id: T.must(new_repository).id
        }
        hash[key_column] = new_record.id
        hash
      end
      model = class_name == "Issue" ? IssueReaction : IssueCommentReaction
      model.throttle { model.create!(reactions) }
    end
  end

  def copy_comment_content_references(old_comment, new_comment)
    ContentReference.throttle_with_retry do
      ContentReference
        .where(content_id: old_comment.id)
        .update_all(content_id: new_comment.id)
    end
  end

  def transfer_close_issue_references
    old_issue = T.must(self.old_issue)

    old_issue.close_issue_references.each do |close_issue_reference|
      close_issue_reference.throttle_with_retry do
        new_issue = T.must(self.new_issue)
        close_issue_reference.update_columns(issue_id: new_issue.id,
                                             issue_repository_id: new_issue.repository_id) # close issue ref is in collab
      end
    end
  end

  def transfer_legacy_project_cards
    old_issue = T.must(self.old_issue)

    old_issue.cards.each do |old_card|
      old_card.throttle_with_retry { old_card.transfer_issue_card(T.must(new_issue).id) }
    end

    # Reload cards we just moved to avoid deleting things with dependent destroys
    old_issue.cards.reload
  end

  def transfer_memex_project_items
    old_issue = T.must(self.old_issue)

    old_issue.memex_project_items.each do |old_item|
      old_item.throttle_with_retry { old_item.transfer_issue_item(new_issue) }
    end
  end

  def transfer_sub_issues
    original_sub_issues = T.must(self.old_issue).sub_issue_relations
    return unless original_sub_issues.present?

    issue_dupe = T.must(new_issue)

    original_sub_issues.in_batches(of: SUB_ISSUE_BATCH_TRANSFER_SIZE) do |batch|
      records_to_add = batch.size
      process_sub_issue_batch(batch)
      new_sub_issues = issue_dupe.reload.sub_issue_relations.last(records_to_add)
      instrument_sub_issue_batch(new_sub_issues)
    end

    SubIssueList.throttle_with_retry do
      issue_dupe.recalculate_sub_issue_list!
    end
  end

  def process_sub_issue_batch(batch)
    issue_dupe = T.must(new_issue)

    new_sub_issues = batch.map do |record|
      attrs = {
        **record.attributes.slice(*SubIssue.column_names).except("id", "source_issue_id", "source_repository_id"),
        source_issue_id: issue_dupe.id,
        source_repository_id: issue_dupe.repository_id
      }
    end

    # We cannot throttle inside of a transaction, because replication begins after the transaction commits.
    # Use wait_for_replication to ensure replication lag is acceptable before committing the transaction.
    wait_for_replication!(SubIssue.cluster_name)
    SubIssue.transaction do
      batch.delete_all
      # insert_all! skips ActiveRecord validation and callbacks, however it is safe
      # to assume the sub-issues are valid on the parent from which we are copying.
      SubIssue.insert_all!(new_sub_issues)
    end
  end

  def instrument_sub_issue_batch(batch)
    issue_dupe = T.must(new_issue)

    GitHub::PrefillAssociations.prefill_associations(batch, [:target, :source])
    batch.each do |sub|
      sub.instrument_transfer_and_notify(T.must(actor), true)
    end
  end

  def transfer_parent_reference
    parent_sub_issue = T.must(self.old_issue).parent_issue_relation

    if parent_sub_issue.present?
      issue_dupe = T.must(new_issue)

      attrs = {
        **parent_sub_issue.attributes.slice(*SubIssue.column_names).except("id", "target_issue_id"),
        target_issue_id: issue_dupe.id,
      }

      # We cannot throttle inside of a transaction, because replication begins after the transaction commits.
      # Use wait_for_replication to ensure replication lag is acceptable before committing the transaction.
      wait_for_replication!(SubIssue.cluster_name)
      SubIssue.transaction do
        parent_sub_issue.delete
        # The new-issue should not have a parent, but this gives us extra certainty that our new tree is valid
        issue_dupe.parent_issue_relation&.delete

        if SubIssue.build(attrs).valid?
          # insert without invoking callbacks
          SubIssue.insert!(attrs)
        end
      end
      issue_dupe.reload.parent_issue_relation&.instrument_transfer_and_notify(T.must(actor))
    end
  end

  def copy_references
    # when the `new_issue`'s comments and body is created, cross references are created.
    # These operations concern references to the new issue.
    copy_references_to_new_issue
    copy_referencing_issues_references
    adjust_created_at_for_references
    delete_outgoing_references_for_old_issue
  end

  def copy_references_to_new_issue
    old_issue = T.must(self.old_issue)
    new_issue = T.must(self.new_issue)

    # old_issue.references will select xrefs where target_id==old_issue.id
    # So we're using the linked entity's info for identification
    xref_key = -> (xref) { [xref.source_id, xref.source_type, xref.created_at] }
    existing_xrefs = new_issue.references.map { |xref| xref_key.call(xref) }
    old_issue.references.
      reject { |xref| existing_xrefs.include?(xref_key.call(xref)) }.
      each do |reference|
        reference.throttle_with_retry do
          dup = reference.dup
          dup.target_id = T.must(new_issue.id)
          dup.target_repository_id = new_issue.repository_id
          dup.created_at = T.unsafe(reference).created_at

          CrossReference.throttle_with_retry { dup.save }
          reference.destroy
        end
      end
  end

  def copy_referencing_issues_references
    preload_references

    # update referencing issue's body and comments links
    T.must(new_issue).references.reload.each do |reference|
      next if reference.source_type != "Issue"

      referencing_issue = reference.source
      next if referencing_issue.nil?

      referencing_issue.transfer = true
      copy_referencing_issue_cross_refs(referencing_issue)
      update_body_mentions(referencing_issue)
      update_comment_body_mentions(referencing_issue)
    end
  end

  def adjust_created_at_for_references
    # Must execute after new issue has its body and comments created.
    # Those modifications creates cross-references, however these
    # must be adjusted.
    old_issue_references = CrossReference.from(old_issue)
    new_issue_references = CrossReference.from(new_issue)

    xref_key = -> (xref) { [xref.target_id, xref.target_type] }
    old_mappings = create_issue_reference_mappings(old_issue_references, xref_key)
    new_mappings = create_issue_reference_mappings(new_issue_references, xref_key)

    new_mappings.each do |mapping, value|
      created_at = old_mappings[mapping]&.created_at
      next if created_at.nil?

      CrossReference.throttle_with_retry { value.update_column(:created_at, created_at) }
    end
  end

  def delete_outgoing_references_for_old_issue
    # Destroy outgoing references from the old issue.
    CrossReference.from(old_issue).each { |xref| xref.throttle_with_retry { xref.destroy } }
  end

  def create_issue_reference_mappings(issue_references, xref_key)
    # There's an unique key on the `cross_references` on columns
    # (source_id, source_type, target_id, target_type), hence
    # just pick the first item in each array (there's only one).
    issue_references
      .group_by { |xref| xref_key.call(xref) }
      .transform_values { |arr| arr.first }
  end

  def preload_references
    # load all referenced source issues

    issue_source_promises = T.must(new_issue).references.select { |r| r.source_type == "Issue" }.map { |r| r.async_source }
    associations = [:comments, :references, :repository].freeze
    Promise.all(issue_source_promises).then do |referencing_issues|
      ActiveRecord::Associations::Preloader.new(
        records: referencing_issues.compact,
        associations: associations,
        available_records: []
      ).call
    end.sync
  end

  def preload_events_and_details
    old_issue = T.must(self.old_issue)
    new_issue = T.must(self.new_issue)

    ActiveRecord::Associations::Preloader.new(records: [old_issue, new_issue], associations: [:events], available_records: []).call
    ActiveRecord::Associations::Preloader.new(records: old_issue.events + new_issue.events, associations: [:issue_event_detail, :actor], available_records: []).call
  end

  def copy_referencing_issue_cross_refs(referencing_issue)
    old_issue = T.must(self.old_issue)
    new_issue = T.must(self.new_issue)

    # A 2nd cross ref was created for the referencing issue when we created `new_issue`
    # It has a new timestamp so we need to update it
    old_issue_refs = referencing_issue.references.select { |r| r.source_id == old_issue.id }
    oldest_ref = old_issue_refs.min_by { |r| r.created_at }
    if old_issue_refs.size > 0
      existing_ref = referencing_issue.references.find { |r| r.source_id == new_issue.id }
      if existing_ref.nil?
        existing_ref = oldest_ref.dup
        existing_ref.source_id = new_issue.id
        existing_ref.source_repository_id = new_issue.repository_id
      end

      existing_ref.created_at = oldest_ref.created_at

      CrossReference.throttle_with_retry { existing_ref.save }
      old_issue_refs.map { |r| r.throttle_with_retry { r.destroy } }
    end
  end

  def update_body_mentions(referencing_issue)
    referencing_issue.body = replace_body_mentions(
      referencing_issue.body.dup,
      source_issue_repo_id: referencing_issue.repository.id,
      target_issue: new_issue)

    referencing_issue.throttle_with_retry { referencing_issue.save touch: update_body_with_touch }
  end

  def update_comment_body_mentions(referencing_issue)
    referencing_issue.comments.each do |comment|
      comment.throttle_with_retry do
        comment.issue_transfer = true
        comment.body = replace_body_mentions(
          comment.body.dup,
          source_issue_repo_id: referencing_issue.repository.id,
          target_issue: new_issue
        )

        comment.save touch: update_body_with_touch
      end
    end
  end

  def update_body_with_touch
    return @update_body_with_touch if defined?(@update_body_with_touch)

    # the feature flag is a kill switch, when removing this feature flag, make sure to replace it with `false`
    @update_body_with_touch = GitHub.flipper[:issue_transfer_update_body_with_touch].enabled?

    @update_body_with_touch
  end

  def set_initial_state
    self.state = "started"
  end

  def set_old_issue_number
    old_issue = T.must(self.old_issue)
    self.old_issue_number = T.must(old_issue.number)
  end

  # Replaces bare issue references `#1` in issue or comment body with
  # global repo issue reference `user/project#num`
  # Inspired by / borrowed from GitHub::HTML::IssueMentionFilter#replace_bare_issue_mentions
  #
  # @param body [String, nil] - the body from the `old_issue` or issue comment
  #
  # @return [String, nil]
  def replace_bare_issue_mentions(body, source_issue_repo_id = nil, target_issue = nil)
    return body if body.nil?

    old_issue = T.must(self.old_issue)
    old_repository = T.must(self.old_repository)

    issue_reference_text = /(?<=\s|^)(gh-|#)(\d+)\b/i

    body.gsub(issue_reference_text) do |match|
      _pound, number = $1, $2.to_i
      if !target_issue.nil? && number == old_issue.number && source_issue_repo_id == old_repository.id
        "#{target_issue.repository.name_with_display_owner}##{target_issue.number}"
      elsif issue_transfer = IssueTransfer.find_by(old_repository_id: old_repository.id, old_issue_number: number)
        # the referenced issue was transferred, too
        if transferred_issue = issue_transfer.new_issue
          "#{T.must(transferred_issue.repository).name_with_display_owner}##{transferred_issue.number}"
        elsif transferred_deleted_issue = DeletedIssue.find_by(old_issue_id: issue_transfer.new_issue_id)
          # the referenced issue was transferred, then deleted
          "#{T.must(transferred_deleted_issue.repository).name_with_display_owner}##{transferred_deleted_issue.number}"
        else
          # the referenced issue was transferred and is missing for other reasons.
          # just leave the reference alone to not break the transfer
          match
        end
      elsif issue = old_repository.issues.find_by(number: number)
        # link to the old repository
        "#{old_repository.name_with_display_owner}##{number}"
      else
        match
      end
    end
  end

  # Replace reference mentions so they fit the new issue (post-transfer)
  # For example old_issue was: github/memex#123 or https://github.com/github/memex/issues/123
  # and was moved to github/projectsVnext#50
  # We replace <github/memex#123 or https://github.com/github/memex/issues/123> with <github/projectsVnext#50>
  def replace_reference_mentions(body)
    return body if body.nil?

    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    body.gsub(reference_patterns) do |match|
      match = T.must(Regexp.last_match)
      full_url_reference = false

      # REPO_ISSUE_REFERENCE match e.g. "github/memex#123".
      repo_prefix, repo_nwo, repo_issue_number = match[1], match[2], match[3]
      if repo_nwo.nil? && repo_issue_number.nil?
        full_url_reference = true
        repo_nwo, repo_issue_number = match[4], match[5]
      end

      if repo_issue_number &&
        repo_nwo&.include?("/") &&
        repo_nwo == T.must(old_issue.repository).name_with_display_owner &&
        repo_issue_number.to_i == old_issue.number

        # this used to link to the old issue, update body to point to the new issue
        if full_url_reference
          "#{GitHub.url}/#{T.must(new_issue.repository).name_with_display_owner}/issues/#{new_issue.number}"
        else
          "#{repo_prefix}#{T.must(new_issue.repository).name_with_display_owner}##{new_issue.number}"
        end
      else
        match[0]
      end
    end
  end

  def get_label_mapping
    new_issue = T.must(self.new_issue)
    old_issue = T.must(self.old_issue)

    # Map old label ids to new label ids.
    # This is needed to handle labels that are considered equal by mysql but differ due to invisible unicode chars.
    source_repo_label_ids = old_issue.events.
      select { |e| LABEL_EVENTS.include?(e.event) && e.label_id.present? }.
      map { |l| T.unsafe(l).label_id }

    # union with the currently assigned labels.
    source_repo_label_ids = source_repo_label_ids.
      union(old_issue.labels.pluck(:id))

    old_to_new_label_id_map = Label.
      where(repository_id: old_issue.repository_id).
      where("labels.id in (?)", source_repo_label_ids).
      joins("join labels as new_labels on new_labels.label_name = labels.label_name").
      where("new_labels.repository_id": new_issue.repository_id).
      pluck("labels.id", "new_labels.id").to_h

    # load target labels
    existing_new_labels_by_id = Label.where(id: old_to_new_label_id_map.values).index_by(&:id)
    old_to_new_label_id_map.map { |k, v| [k, existing_new_labels_by_id[v]] }.to_h
  end

  def get_old_milestone_mapping
    old_issue = T.must(self.old_issue)

    # Map milestone id (in old issue repo) to their due date
    # This is needed since the milestone events don't contain the due date
    source_repo_milestone_ids = old_issue.events.select { |e| MILESTONE_EVENTS.include?(e.event) && e.milestone_id.present? }.
      map { |e| T.unsafe(e).milestone_id }.uniq

    milestone_id_to_due_date = source_repo_milestone_ids.map do |milestone_id|
      milestone = T.must(old_issue.repository).milestones.find_by(id: milestone_id)
      if milestone.present?
        [milestone.id, milestone.due_on]
      end
    end

    # filter out entries which didn't have a milestone.
    milestone_id_to_due_date.compact.to_h
  end

  def transferrable_by_actor
    old_issue = T.must(self.old_issue)

    if !old_issue.transferrable_by?(actor)
      errors.add(:old_issue, "is not transferrable")
    end
  end

  def with_same_owner
    unless T.must(new_repository).owner_id == T.must(old_repository).owner_id
      errors.add(:new_repository, "must have the same owner as the current repository")
    end
  end

  def not_transferring_private_to_public
    if T.must(old_repository).private? && T.must(new_repository).public?
      errors.add(:old_issue, "cannot be transferred from private repository to public repository")
    end
  end

  def actor_permissions
    actor = T.must(self.actor)

    acting_user = actor.bot? ? T.unsafe(actor).installation : actor
    unless T.must(new_repository).resources.contents.writable_by?(acting_user)
      errors.add(:actor, "must have write permissions on new repository")
    end

    unless T.must(old_repository).resources.contents.writable_by?(acting_user)
      errors.add(:actor, "must have write permissions on old repository")
    end
  end

  def old_issue_unlocked
    if T.must(old_issue).locked?
      errors.add(:old_issue, "cannot be locked")
    end
  end

  def repos_not_archived
    if T.must(new_repository).archived?
      errors.add(:new_repository, "must not be archived")
    end

    if T.must(old_repository).archived?
      errors.add(:old_repository, "must not be archived")
    end
  end

  def repos_have_issues
    if !T.must(new_repository).has_issues?
      errors.add(:new_repository, "must have issues enabled")
    end

    if !T.must(old_repository).has_issues?
      errors.add(:old_repository, "must have issues enabled")
    end
  end

  def transfer_subscribers
    GitHub.newsies.async_copy_thread_subscribers(old_issue, new_issue)
  end

  def reference_patterns
    Regexp.union(
      GitHub::HTML::IssueMentionFilter::REPO_ISSUE_REFERENCE,
      GitHub::HTML::IssueMentionFilter.full_url_issue_mention,
    )
  end

  private def wait_for_replication!(store_name)
    WaitForReplication.new(
      Timestamp.from_time(Time.now.utc),
      store_name:,
      max_wait_seconds: SUB_ISSUE_MAX_REPLICATION_WAIT_TIME
    ).wait!
  end
end
