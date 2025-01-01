# typed: false
# frozen_string_literal: true

class UserContentEdit < ApplicationRecord::Domain::UserContentEdits
  include FilterPipelineHelper
  include Instrumentation::Model

  module Core
    extend ActiveSupport::Concern

    included do |_base|
      belongs_to :editor, class_name: "User"
      belongs_to :deleted_by, class_name: "User"
      # rubocop:todo Rails/InverseOf
      belongs_to :performed_via_integration, foreign_key: "performed_by_integration_id", class_name: "Integration"
      # rubocop:enable Rails/InverseOf
    end

    class_methods do
      def matching_user_content(user_content_edit)
        where(user_content_id: user_content_edit.user_content_id)
      end
    end

    def event_prefix
      "user_content_edit"
    end

    def platform_type_name
      "UserContentEdit"
    end

    def async_viewer_can_read?(viewer)
      async_user_content.then do |user_content|
        user_content&.async_viewer_can_read_user_content_edits?(viewer)
      end
    end

    def viewer_can_read?(viewer)
      async_viewer_can_read?(viewer).sync
    end

    def async_viewer_can_delete?(viewer)
      return Promise.resolve(false) unless viewer
      return Promise.resolve(true) if viewer.id == editor_id

      async_user_content.then do |user_content|
        user_content.async_viewer_can_delete_user_content_edits?(viewer)
      end
    end

    def viewer_can_delete?(viewer)
      async_viewer_can_delete?(viewer).sync
    end

    def event_payload
      {
        user_content_type: user_content_type,
        user_content_id: user_content_id,
        editor: self.editor&.login,
        editor_id: self.editor&.id,
      }
    end

    # Removes the public diff and marks the user and when it was "deleted"
    def soft_delete!(user)
      content = safe_diff
      transaction do
        # need to purge the sensitive content
        touch(:deleted_at)
        update(diff: "deleted", deleted_by: user)
      end
      instrument :delete, deleted_by: user.display_login, deleted_by_id: user.id, deleted_at: self.deleted_at, deleted_content: content
    end

    # Finds the content for this user_content_edit to compare it to for diff view
    def diff_before
      edit = self.prev_edit
      edit.nil? ? "" : edit.diff
    end

    # Ensure that everything coming back is UTF-8 this ensures that emoji don't break things
    def safe_diff
      transcode_yaml_value(self.diff)
    end

    def safe_diff_before
      transcode_yaml_value(self.diff_before)
    end

    # Find the previous user content edit
    def prev_edit
      self.class.matching_user_content(self).where("id < ? AND deleted_at IS NULL", self.id).order(id: :desc).limit(1).first
    end

    def newest?
      self.class.matching_user_content(self).where("id > ?", self.id).empty?
    end

    def first_edit?
      self.class.matching_user_content(self).where("id < ?", self.id).empty?
    end
  end

  include Core

  # Overwrites UserContentEdit::Core.matching_user_content to include `user_content_type`
  def self.matching_user_content(user_content_edit)
    super(user_content_edit).where(user_content_type: user_content_edit.user_content_type)
  end

  belongs_to :user_content, polymorphic: true

  def global_id
    if self.user_content_type == "GistComment"
      async_id = self.async_user_content.then do |user_content|
        user_content.async_gist.then do |gist|
          "#{gist.repo_name}:#{id}"
        end
      end

      async_id.sync
    else
      super
    end
  end

  after_create :dual_write_user_content_edit
  after_update :dual_write_user_content_edit
  after_destroy :dual_write_user_content_edit_on_destroy

  def dual_write_user_content_edit
    return unless GitHub.flipper[:user_content_edits_double_write].enabled?

    klass = case user_content_type
    when "GistComment", "DiscussionPost", "DiscussionPostReply", "OrganizationDiscussionPost"
      "#{user_content_type}Edit".constantize
    else
      return # Nothing to do here
    end

    foreign_key = user_content_type.foreign_key

    klass.connection.execute(klass.sanitize_sql([<<~SQL, id: id]))
      INSERT INTO #{klass.quoted_table_name} (
        id,
        #{foreign_key},
        edited_at,
        editor_id,
        created_at,
        updated_at,
        performed_by_integration_id,
        deleted_at,
        deleted_by_id,
        diff,
        user_content_edit_id
      ) SELECT
        id,
        user_content_id AS #{foreign_key},
        edited_at,
        editor_id,
        created_at,
        updated_at,
        performed_by_integration_id,
        deleted_at,
        deleted_by_id,
        diff,
        id AS user_content_edit_id
      FROM user_content_edits
      WHERE
        id = :id
      ON DUPLICATE KEY UPDATE
        #{foreign_key} = user_content_edits.user_content_id,
        edited_at = user_content_edits.edited_at,
        editor_id = user_content_edits.editor_id,
        created_at = user_content_edits.created_at,
        updated_at = user_content_edits.updated_at,
        performed_by_integration_id = user_content_edits.performed_by_integration_id,
        deleted_at = user_content_edits.deleted_at,
        deleted_by_id = user_content_edits.deleted_by_id,
        diff = user_content_edits.diff,
        user_content_edit_id = user_content_edits.id
      /* cross-schema-domain-query-exempted */
    SQL
  end

  def dual_write_user_content_edit_on_destroy
    return unless GitHub.flipper[:user_content_edits_double_write].enabled?

    klass = case user_content_type
    when "GistComment", "DiscussionPost", "DiscussionPostReply", "OrganizationDiscussionPost"
      "#{user_content_type}Edit".constantize
    else
      return # Nothing to do here
    end

    klass.where(user_content_edit_id: id).destroy_all
  end
end
