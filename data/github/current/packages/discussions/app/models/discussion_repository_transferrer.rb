# typed: true
# frozen_string_literal: true

# Public: Used to move a Discussion to another Repository, updating
# all the necessary records to do so and recording the move via a
# DiscussionTransfer record.
class DiscussionRepositoryTransferrer
  BATCH_SIZE = 50

  # Public: Used to start the transfer process.
  #
  # discussion - the Discussion to move to a different repository
  # new_repository - the Repository to move the discussion to
  # actor - the User who is initiating the transfer
  #
  # Returns a DiscussionRepositoryTransferrer.
  sig { params(discussion: Discussion, new_repository: Repository, actor: User).returns(DiscussionRepositoryTransferrer) }
  def self.for_new_transfer(discussion, new_repository:, actor:)
    new(discussion: discussion, new_repository: new_repository, actor: actor)
  end

  # Public: Used to finish an already begun transfer of a discussion.
  #
  # discussion_transfer - the DiscussionTransfer record created when the transfer
  #                       was begun
  #
  # Returns a DiscussionRepositoryTransferrer.
  sig { params(discussion_transfer: DiscussionTransfer).returns(DiscussionRepositoryTransferrer) }
  def self.for_continuing_transfer(discussion_transfer)
    new(discussion_transfer: discussion_transfer)
  end

  attr_reader :old_discussion, :error, :new_repository, :new_discussion,
    :discussion_transfer, :actor, :old_repository

  # discussion - the Discussion to move; required if `discussion_transfer` is nil
  # actor - the currently authenticated User; required if `discussion_transfer` is nil
  # new_repository - the Repository the discussion should be moved to; required
  #                  if `discussion_transfer` is nil
  # discussion_transfer - the DiscussionTransfer record for an already-in-progress
  #                       transfer; required if `new_repository` is nil
  sig do params(
    discussion: T.nilable(Discussion),
    actor: T.nilable(User),
    new_repository: T.nilable(Repository),
    discussion_transfer: T.nilable(DiscussionTransfer)
  ).void
  end
  def initialize(discussion: nil, actor: nil, new_repository: nil, discussion_transfer: nil)
    if new_repository.nil? && discussion_transfer.nil?
      raise "Either the new repository or an existing transfer record must be provided"
    end

    if discussion.nil? && discussion_transfer.nil?
      raise "Either the old discussion or an existing transfer record must be provided"
    end

    if discussion_transfer
      @old_discussion = discussion_transfer.old_discussion
      @old_repository = discussion_transfer.old_repository
      @actor = discussion_transfer.actor || User.ghost
      @discussion_transfer = discussion_transfer
      @new_discussion = discussion_transfer.new_discussion
      @new_repository = discussion_transfer.new_repository
    else
      @old_discussion = discussion
      @old_repository = T.must(discussion).repository
      @actor = actor
      @discussion_transfer = DiscussionTransfer.new(
        old_discussion: discussion,
        old_repository: T.must(discussion).repository,
        new_repository: new_repository,
        actor: actor,
      )
      @new_discussion = nil
      @new_repository = new_repository
    end

    @error = nil
  end

  # Public: Start the transfer process, safe to run synchronously when the user
  # requests a discussion transfer. Will create a new Discussion in the new
  # repository and log that the transfer has started by making a new
  # DiscussionTransfer.
  #
  # Returns a Boolean indicating success.
  sig { returns(T::Boolean) }
  def start_transfer
    # Transfer has already begun
    return true if discussion_transfer.persisted?

    unless old_discussion.can_transfer_to?(new_repository, actor: actor)
      @error = "That repository is not a valid destination for this discussion."
      return false
    end

    unless new_category_id
      @error = categories_type_error_message
      return false
    end

    @new_discussion = Discussion.new(
      repository: new_repository,
      user: old_discussion.user,
      title: old_discussion.title,
      body: replace_bare_discussion_mentions(old_discussion.body.dup),
      comment_count: old_discussion.comment_count,
      state: :transferring,
      user_hidden: old_discussion.user_hidden,
      created_at: old_discussion.created_at,
      category_id: new_category_id,
      chosen_comment_id: old_discussion.chosen_comment_id,
      bumped_at: old_discussion.bumped_at,
    )

    if old_discussion.poll.present?
      if !new_discussion.category&.supports_polls?
        @error = "Unable to transfer discussion to #{new_repository.name_with_owner} " \
          "because the repository doesn't have any categories that support polls."
        return false
      end

      poll = old_discussion.poll
      @new_discussion.poll = DiscussionPoll.new(
        discussion: @new_discussion,
        question: poll.question,
        discussion_poll_votes_count: poll.discussion_poll_votes_count,
        created_at: old_discussion.created_at,
        updated_at: old_discussion.updated_at
      )

      option_attributes = poll.options.pluck(:option).map { |option| { option: option } }
      T.must(@new_discussion.poll).options.build(option_attributes)
    end

    unless @new_discussion.save
      @error = error_message("Failed to create a copy of the discussion in " \
        "#{new_repository.name_with_owner}:", @new_discussion)
      return false
    end

    discussion_transfer.new_discussion = @new_discussion

    unless discussion_transfer.save
      @error = error_message("Failed to record discussion transfer:", discussion_transfer)
      return false
    end

    true
  end

  # Public: Allow undoing a transfer that has not yet completed successfully.
  #
  # Returns a Boolean indicating success.
  sig { returns(T::Boolean) }
  def revert_started_transfer
    unless discussion_transfer.persisted?
      @error = "Cannot revert a transfer that has not started."
      return false
    end

    if discussion_transfer.done?
      @error = "Cannot revert a transfer that has already finished."
      return false
    end

    unless Discussion.exists?(old_discussion.id)
      @error = "Cannot revert a transfer where discussion in old repository has " \
        "already been deleted."
      return false
    end

    unless new_discussion.destroy
      @error = error_message("Could not delete partially transferred discussion " \
        "from #{new_repository.name_with_owner}:", new_discussion)
      return false
    end

    unless discussion_transfer.destroy
      @error = error_message("Could not delete transfer record:", discussion_transfer)
      return false
    end

    true
  end

  # Public: Finish an already started transfer. Should be run in a background job
  # since it may take some time to complete.
  #
  # staff_user - optional User to use when recording the audit log event
  #              for the transfer
  #
  # Returns a Boolean indicating success.
  sig { params(staff_user: T.nilable(User)).returns(T::Boolean) }
  def complete_transfer(staff_user = nil)
    unless discussion_transfer.persisted?
      @error = "Cannot complete a discussion transfer that hasn't started."
      return false
    end

    unless discussion_transfer.started?
      @error = "This discussion transfer has already finished."
      return false
    end

    unless old_discussion
      @error = "Original discussion has since been deleted."
      return false
    end

    unless old_discussion.can_transfer_to?(new_repository, actor: actor)
      @error = "#{actor} does not have permission to finish transferring this discussion."
      return false
    end

    move_events
    move_comments
    move_user_content_edits
    move_reactions
    transfer_labels
    copy_subscribers

    transfer_event = new_discussion.events.new(actor: actor, event_type: :transferred)
    unless transfer_event.save
      @error = error_message("Could not record discussion event about transfer:", transfer_event)
      discussion_transfer.errored!
      return false
    end

    new_discussion.state = old_discussion.state
    new_discussion.state_reason = old_discussion.state_reason
    new_discussion.error_reason = old_discussion.error_reason
    new_discussion.issue_id = old_discussion.issue_id
    unless new_discussion.save
      @error = error_message("Could not save new discussion data:", new_discussion)
      discussion_transfer.errored!
      return false
    end

    discussion_transfer.instrument_transfer_event(staff_user)

    old_discussion.actor = actor
    old_discussion.deletion_hook_action = :transferred
    unless old_discussion.destroy
      @error = error_message("Could not delete discussion from old repository:", old_discussion)
      discussion_transfer.errored!
      return false
    end

    discussion_transfer.state = :done
    discussion_transfer.new_discussion_event = transfer_event

    unless discussion_transfer.save
      @error = error_message("Could not mark transfer as complete:", discussion_transfer)
      return false
    end

    new_discussion.synchronize_search_index

    true
  end

  private

  # Private: Get the ID of the new repository-equivalent category to the old discussion's
  # category, if such a category exists.
  sig { returns(T.nilable(Integer)) }
  def new_category_id
    old_category = old_discussion.category
    return unless old_category

    # When transferring a discussion, just look for a category with the same name and type. If same name
    # and type category does not exist, try finding first available category that matches the old category's type.
    same_name_category = new_repository.available_discussion_categories.find_by(
      name: old_category.name,
      supports_polls: old_category.supports_polls?,
      supports_mark_as_answer: old_category.supports_mark_as_answer?,
      supports_announcements: old_category.supports_announcements?,
    )

    new_category = same_name_category || new_repository.available_discussion_categories.find_by(
      supports_polls: old_category.supports_polls?,
      supports_mark_as_answer: old_category.supports_mark_as_answer?,
      supports_announcements: old_category.supports_announcements?,
    )
    new_category&.id
  end

  sig { returns(ActiveRecord::Associations::CollectionProxy) }
  def transfer_labels
    old_to_new_label_mapping = get_label_mapping

    new_labels = old_discussion.labels.map do |label|
      target_label = old_to_new_label_mapping[label.id]

      if target_label.present?
        target_label
      else
        label.throttle_with_retry do
          new_discussion.repository.labels.create!(
            name: label.name,
            lowercase_name: label.lowercase_name,
            color: label.color,
            created_at: label.created_at
          )
        end
      end
    end

    new_discussion.labels << new_labels.difference(new_discussion.labels) # difference to avoid adding existing labels.
  end

  sig { void }
  def move_events
    old_discussion.events.in_batches(of: BATCH_SIZE) do |scope|
      ApplicationRecord::Domain::Discussions.throttle do
        scope.update_all(discussion_id: new_discussion.id, repository_id: new_repository.id)
      end
    end
  end

  sig { void }
  def move_comments
    comments = old_discussion.comments

    comments.in_batches(of: BATCH_SIZE) do |scope|
      ApplicationRecord::Domain::Discussions.throttle do
        scope.each do |comment|
          comment.update_column(:body, replace_bare_discussion_mentions(comment.body.dup))
        end
        scope.update_all(discussion_id: new_discussion.id, repository_id: new_repository.id)
      end
    end
  end

  # Private: Replaces bare discussion references `#1` in discussion or comment body with
  # global repo discussion reference `user/project#num`.
  # Inspired by / borrowed from GitHub::HTML::IssueMentionFilter#replace_bare_discussion_mentions
  #
  # body - the body from the `old_discussion`; String or nil
  sig { params(body: T.nilable(String)).returns(T.nilable(String)) }
  def replace_bare_discussion_mentions(body)
    return body if body.nil?

    discussion_reference_text = /(?<=\s|^)(gh-|#)(\d+)\b/i

    body.gsub(discussion_reference_text) do |match|
      _pound, number = $1, $2.to_i

      if discussion = old_repository.discussions.find_by(number: number)
        # link to the old repository
        next "#{old_repository.name_with_owner}##{number}"
      end

      transfer = DiscussionTransfer.find_by(old_repository_id: old_repository.id, old_discussion_number: number)

      transferred_repo = transfer&.new_discussion&.repository
      if transferred_repo
        transfer = T.must(transfer)
        new_discussion = T.must(transfer.new_discussion)
        "#{transferred_repo.name_with_owner}##{new_discussion.number}"
      else
        match
      end
    end
  end

  sig { void }
  def move_user_content_edits
    old_discussion.user_content_edits.in_batches(of: BATCH_SIZE) do |scope|
      ApplicationRecord::Domain::Discussions.throttle do
        scope.update_all(discussion_id: new_discussion.id)
      end
    end
  end

  sig { void }
  def move_reactions
    old_discussion.reactions.in_batches(of: BATCH_SIZE) do |scope|
      ApplicationRecord::Domain::Discussions.throttle do
        scope.update_all(discussion_id: new_discussion.id)
      end
    end
  end

  sig { void }
  def copy_subscribers
    GitHub.newsies.async_copy_thread_subscribers(old_discussion, new_discussion)
  end

  sig { returns(ActiveRecord::Relation) }
  def users_ignoring_old_discussion
    User.where(id: old_discussion_subscriber_set.ignored).select(:id)
  end

  sig { returns(T.any(Newsies::SubscriberSet, Newsies::EmptySubscriberSet)) }
  def old_discussion_subscriber_set
    GitHub.newsies.subscriber_set_for(list: old_repository, thread: old_discussion)
  end

  sig { params(prefix: String, record: T.any(Discussion, DiscussionTransfer, DiscussionEvent)).returns(String) }
  def error_message(prefix, record)
    "#{prefix} #{record.errors.full_messages.to_sentence}"
  end

  sig { returns(T::Hash[Integer, Label]) }
  def get_label_mapping
    source_repo_label_ids = old_discussion.labels.pluck(:id)
    old_to_new_label_id_map = Label.
      where(repository_id: old_discussion.repository_id).
      where("labels.id in (?)", source_repo_label_ids).
      joins("join labels as new_labels on new_labels.label_name = labels.label_name").
      where("new_labels.repository_id": new_discussion.repository_id).
      pluck("labels.id", "new_labels.id").to_h

    # load target labels
    existing_new_labels_by_id = Label.where(id: old_to_new_label_id_map.values).index_by(&:id)
    old_to_new_label_id_map.map { |k, v| [k, existing_new_labels_by_id[v]] }.to_h
  end

  sig { returns(String) }
  def categories_type_error_message
    category_type = if old_discussion.category.supports_polls?
      "polls"
    elsif old_discussion.category.supports_mark_as_answer?
      "answers"
    elsif old_discussion.category.supports_announcements?
      "announcements"
    else
      "open-ended discussions"
    end
    "Unable to transfer discussion to #{new_repository.name_with_owner} because the repository " \
      "does not have any discussion categories that support #{category_type}."
  end
end
