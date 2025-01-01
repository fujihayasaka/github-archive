# typed: false
# frozen_string_literal: true

module UserContentEditable
  extend ActiveSupport::Concern
  extend Scientist

  # Classes named here mix in UserContentEditable but use an edit class other
  # than UserContentEdit. By convention, these are ActiveRecord models named
  # "#{base}Edit" - for example, a CommitComment's edit class is
  # CommitCommentEdit.
  CUSTOM_EDIT_CLASS_NAMES = {
    "CommitComment" => "CommitCommentEdit",
    "Discussion" => "DiscussionEdit",
    "DiscussionComment" => "DiscussionCommentEdit",
    "Issue" => "IssueEdit",
    "IssueComment" => "IssueCommentEdit",
    "PullRequestReview" => "PullRequestReviewEdit",
    "PullRequestReviewComment" => "PullRequestReviewCommentEdit",
    "RepositoryAdvisory" => "RepositoryAdvisoryEdit",
    "RepositoryAdvisoryComment" => "RepositoryAdvisoryCommentEdit",
  }.freeze

  # Some vitess supported class need to provide sharding keys to dependent_destroy
  # The value for each class is [sharding_key, sharding_value_key]
  CUSTOM_SHARDING_KEYS_FOR_DESTROY = {
    "CommitComment" => [:repository_id, :repository_id],
    "Issue" => [:repository_id, :repository_id],
    "IssueComment" => [:repository_id, :repository_id],
    "PullRequestReview" => [:repository_id, :repository_id],
    "PullRequestReviewComment" => [:repository_id, :repository_id],
  }.freeze

  # Public: Return the name of the ActiveRecord model used to store content edits
  # for a class that stores user content.
  #
  # "classname" is expected to be a model that includes the UserContentEdit::Core
  # model, but this is not enforced.
  def self.edit_class_for(classname)
    CUSTOM_EDIT_CLASS_NAMES.fetch(classname, "UserContentEdit")
  end

  # Public: Return true if a String matches a known custom edit class' name.
  def self.is_custom_edit_class?(classname)
    CUSTOM_EDIT_CLASS_NAMES.has_value?(classname)
  end

  included do |base|
    if edit_class_name = CUSTOM_EDIT_CLASS_NAMES[base.name]
      has_many :user_content_edits, class_name: edit_class_name
      has_one :latest_user_content_edit, -> { order("id DESC") }, class_name: edit_class_name
      if CUSTOM_SHARDING_KEYS_FOR_DESTROY.include?(base.name)
        sharding_key, sharding_value_key = CUSTOM_SHARDING_KEYS_FOR_DESTROY[base.name]
        destroy_dependents_in_background :user_content_edits, sharding_key: sharding_key, sharding_value_key: sharding_value_key
      else
        destroy_dependents_in_background :user_content_edits
      end

    else
      has_many :user_content_edits, as: :user_content
      has_one :latest_user_content_edit, -> { order("id DESC") }, as: :user_content, class_name: "UserContentEdit"
    end


    def async_latest_user_content_edit
      (self.is_a?(PullRequest) ? async_issue : Promise.resolve(self)).then do |comment|
        if comment.association(:latest_user_content_edit).loaded?
          next Promise.resolve(comment.latest_user_content_edit)
        end
        load_latest_user_content_edit(comment: comment).then do |latest_edit|
          comment.association(:latest_user_content_edit).target = latest_edit
          latest_edit
        end
      end
    end

    # Public: Determines if the content has been edited and the content edits include the creation edit.
    #
    # This is considered true if there are multiple edits and the first two were created at the same time.
    #
    # Returns a Promise which resolves to a Boolean.
    def async_includes_created_edit?
      (self.is_a?(PullRequest) ? self.async_issue : Promise.resolve(self)).then do |editable|
        Platform::Loaders::IncludesCreatedEdit.load(editable.class, editable.id)
      end
    end

    # Public: Was the content edited by someone besides the original author?
    #
    # Returns a Promise which resolves to a Boolean.
    def async_edited_by_another_user?
      (self.is_a?(PullRequest) ? self.async_issue : Promise.resolve(self)).then do |editable|
        if editable.association(:latest_user_content_edit).loaded? && editable.latest_user_content_edit.nil?
          next Promise.resolve(false)
        end

        Platform::Loaders::EditedByAnotherUser.load(editable.class, editable.id)
      end
    end
  end

  # Public: Updates this content's `body` attribute. Creates or updates the
  # UserContentEdit record to track the change.
  #
  # Optionally updates the formatter field of this content at the same time.
  #
  # body - String of text to set as the `body` field of this record
  # editor - User who is making the change
  # old_diff - optional String to record in the user content edit representing the original `body` of this record;
  #            defaults to `body_was`; only used when no original user content edit record exists for this record
  # new_diff - optional String to record in the `diff` field of the user content edit that corresponds to the given
  #            `body`; defaults to the same value as `body`
  #
  # Returns a Boolean.
  def update_body(body, editor, formatter: nil, performed_via_integration: nil, new_diff: nil, old_diff: nil)
    # from time to time, this transaction can throw transient exceptions from the DB layer. In such cases, retry.
    retries_left = 2

    begin
      saved = transaction do
        old_diff ||= body_was
        new_diff ||= body
        now = Time.current

        if track_edits? && new_diff != old_diff
          unless user_content_edits.any?
            # create the "initial commit" type edit
            user_content_edits.create!(created_at: now, performed_via_integration: performed_via_integration,
              editor: user || User.ghost, diff: old_diff, edited_at: created_at || now)
          end

          user_content_edits.create!(editor: editor, edited_at: now, created_at: now,
            performed_via_integration: performed_via_integration, diff: new_diff)
          reload_latest_user_content_edit
        end

        # update body attribute last to make sure correct editor is being used
        # https://github.com/github/github/issues/55468
        attributes = { body: body }
        attributes[:formatter] = formatter if formatter

        saved = update(attributes) # domain-isolation-query-violation:ignore:packages/issues (INSERT, SELECT, UPDATE)

        # rollback the transaction to prevent edit history from being created
        # if updating the issue/discussion/etc. fails.
        raise ActiveRecord::Rollback unless saved

        saved
      end

      if retries_left < 2
        # track that retries are helping.
        GitHub.dogstats.increment("user_content_editable.pass_with_retry", tags: ["object_class:#{self.class.name}"])
      end

      saved
    rescue ActiveRecord::ConnectionFailed => error
      if retries_left > 0
        retries_left -= 1
        user_content_edits.reload

        retry
      end

      # if retries are exhausted:
      # * log data about body etc.q This to see if a pattern can be identified.
      # * re-throw exception.
      #
      # See more at https://github.com/github/issues/issues/4564.
      GitHub.logger.info(
        "Exhausted retries during attempting 'update_body' transaction.",
        {
          "gh.request_id" => GitHub.context[:request_id],
          "code.function" => "#{self.class.name}#update_body",
          "gh.catalog_service" => "github/issues",
          "gh.issues.user_content_editable.object_id" => id,
          "gh.issues.user_content_editable.object_class" => self.class.name,
          "gh.issues.user_content_editable.editor_id" => editor&.id,
          "gh.issues.user_content_editable.new_body_length" => body.length,
          "gh.issues.user_content_editable.old_body_length" => body_was&.length,
          "gh.issues.user_content_editable.tracking_edits" => track_edits?
        }
      )

      raise
    end
  end

  # Public: Creates or updates a UserContentEdit record to track a given change
  # in a given attribute.
  #
  # This method assumes that a) it is being run inside a transaction, and b) the
  # content has already been saved in the parent record.
  #
  # This allows us to keep track of content stored in an attribute other than
  # the "body" attribute.
  #
  # Returns a nil or a UserContentEdit record.
  def add_user_content_edit!(content_was, content_is, editor)
    if track_edits? && content_is != content_was
      edit_params = { editor: editor,
                      edited_at: Time.current,
                      created_at: Time.current }


      if user_content_edits.empty?
        # create the "initial commit" type edit
        user_content_edits.create!(edit_params.merge({ editor: self.user || User.ghost,
                                                       diff: content_was,
                                                       edited_at: (self.created_at || Time.current),
        }))
      end
      user_content_edits.create!(edit_params.merge({ diff: content_is }))
    end
  end

  # Public: The date this content was edited
  #
  # Returns a DateTime
  def edited_at
    return unless edited?
    latest_user_content_edit.edited_at
  end

  # Public: Has this content been edited?
  #
  # Returns a Boolean
  def edited?
    latest_user_content_edit.present?
  end

  # Public: The user who performed the edit
  #
  # Returns a User
  def editor
    async_editor.sync
  end

  # Public: The user who performed the edit
  #
  # Returns a User or nil
  def async_editor
    async_latest_user_content_edit.then do |latest_edit|
      next if latest_edit.nil?
      latest_edit.async_editor
    end
  end

  # Use to determine if the edit history for
  # this particular instance of an object
  # includes an edit that marks the creation
  # of the content
  def includes_created_edit?(content_edits: nil)
    edits = content_edits || user_content_edits
    if edits.count >= 2
      return edits.first.created_at == edits[1].created_at
    end
    false
  end

  # Whether to show the edit history to the given viewer. This default behavior
  # can be overridden per UserContentEditable model.
  def viewer_can_read_user_content_edits?(viewer)
    return @viewer_can_read_user_content_edits if defined? @viewer_can_read_user_content_edits
    async_viewer_can_read_user_content_edits?(viewer).sync
  end

  def async_viewer_can_read_user_content_edits?(viewer)
    if respond_to?(:async_readable_by?)
      async_readable_by?(viewer)
    elsif respond_to?(:readable_by?)
      Promise.resolve(readable_by?(viewer))
    else
      Promise.resolve(false)
    end
  end

  # Whether the given viewer may delete *any* item in the edit history. This
  # default behavior can be overridden per UserContentEditable model.
  #
  # For some users, this will return false meaning that they cannot delete _any_
  # item in the edit history. Still, that same user may be able to delete _some_
  # items in the edit history, i.e., their own.
  #
  # See: UserContentEdit#viewer_can_delete?
  def viewer_can_delete_user_content_edits?(viewer)
    async_viewer_can_delete_user_content_edits?(viewer).sync
  end

  def async_viewer_can_delete_user_content_edits?(viewer)
    if respond_to?(:async_adminable_by?)
      async_adminable_by?(viewer)
    elsif respond_to?(:adminable_by?)
      Promise.resolve(adminable_by?(viewer))
    elsif is_a?(Issue)
      return Promise.resolve(true) if viewer.site_admin?
      return Promise.resolve(true) if viewer.id == self.owner.id

      async_repository.then do |repository|
        next false unless repository
        next true if viewer.id == repository.owner_id

        repository.async_adminable_by?(viewer)
      end
    elsif is_a?(DiscussionItem)
      async_viewer_can_delete?(viewer)
    elsif respond_to?(:async_repository)
      async_repository.then do |repository|
        next false unless repository
        next true if viewer.id == repository.owner_id

        repository.async_pushable_by?(viewer)
      end
    else
      Promise.resolve(false)
    end
  end

  # Was the comment body changed in previous_changes? We use this to determine
  # if body changes _only_ after_commit.
  def body_changed_after_commit?
    body_previously_changed?
  end

  # if body changed _only_ after_commit
  # check if body changed from filled -> nil or empty
  def body_changed_to_nil?
    return false unless body_changed_after_commit?
    old_value, new_value = body_changes
    !old_value.blank? && new_value.blank?
  end

  # if body changed _only_ after_commit
  # check if body changed from nil or empty -> filled
  def body_changed_to_filled?
    return false unless body_changed_after_commit?
    old_value, new_value = body_changes
    old_value.blank? && !new_value.blank?
  end

  private

  # Returns a Promise
  def load_latest_user_content_edit(comment:)
    if comment.instance_of?(IssueComment)
      Platform::Loaders::LatestUserIssueCommentEdit.load(comment.id, comment.repository_id)
    else
      Platform::Loaders::LatestUserContentEdit.load(comment.class, comment.id)
    end
  end

  # load and scrubs the body changes
  def body_changes
    old_value, new_value = previous_changes[:body]
    old_value = old_value.scrub if old_value
    new_value = new_value.scrub if new_value
    [old_value, new_value]
  end

  def track_edits?
    # We should only track edits if the comment is not pending.
    # Not all comment types have states, so we have `try` for the method.
    !try(:pending?) && persisted?
  end
end
