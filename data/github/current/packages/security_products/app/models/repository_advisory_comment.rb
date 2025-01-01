# typed: true
# frozen_string_literal: true

class RepositoryAdvisoryComment < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification
  include GitHub::UserContent
  include EmailReceivable
  include Reaction::Subject::RepositoryContext
  include UserContentEditable
  include NotificationsContent::WithCallbacks
  include RepositoryAdvisory::AfterPublication
  include RepositoryAdvisory::DeliverableNotificationSubscribers
  include Reactable
  include OrgBlockable
  include AbuseReportable
  include Spam::ContentUserIsSpammy
  include PreloadableAttributes
  include AuthorAssociable

  # Sorbet Includes
  include RepositoryAdvisory::DeliverableNotificationSubscribers::NotifiableComment

  attr_preloadable :viewer_can_react, :body_html, :readable_by, :viewer_can_update,
    :viewer_can_read_user_content_edits, :reaction_groups, :reaction_path, :user_is_spammy, :author_association_symbol

  after_commit :subscribe_and_notify, on: :create
  after_commit :update_subscriptions_and_notify, on: :update

  attribute :body, StringFromBinary.new

  belongs_to :repository_advisory
  belongs_to :user

  has_many :reactions, as: :subject

  validates :repository_advisory, presence: true
  validates :user, presence: true
  validates :body, presence: true

  validate :author_must_have_write_permission
  validate :cannot_be_created_after_advisory_publication, on: :form_submission

  def stafftools_url
    UrlHelpers.stafftools_repository_repository_advisory_comment_path(repository.owner, repository.name, repository_advisory_id, id)
  end

  def viewer_can_report(user = nil)
    return @viewer_can_report if defined?(@viewer_can_report)
    return false if user.nil?

    @viewer_can_report = async_viewer_can_report?(user).sync
  end

  def viewer_can_report_to_maintainer
    false
  end

  def viewer_relationship(user = nil)
    return @viewer_relationship if defined?(@viewer_relationship)
    return false if user.nil?

    @viewer_relationship = async_viewer_relationship(user).sync
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  def safe_user
    user || User.ghost
  end

  def belongs_to_spammy_content?
    T.must(repository_advisory).spammy?
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # GitHub::MinimizeComment interface.
  def viewer_can_minimize?(_user = nil)
    false
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # GitHub::MinimizeComment interface.
  def viewer_can_unminimize?(_user = nil)
    false
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # OrgBlockable interface.
  def viewer_can_block_from_org?(user = nil)
    if user.nil?
      if defined? @viewer_can_block_from_org
        return @viewer_can_block_from_org
      else
        return false
      end
    end
    async_viewer_can_block_from_org?(user).sync
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # OrgBlockable interface.
  def viewer_can_unblock_from_org?(user = nil)
    if user.nil?
      if defined? @viewer_can_unblock_from_org
        return @viewer_can_unblock_from_org
      else
        return false
      end
    end
    async_viewer_can_unblock_from_org?(user).sync
  end

  # Hardcoded to maintain a shared interface with Issue and IssueComment types
  def viewer_can_create_issue?(viewer = nil, repo = nil)
    false
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository_advisory.then(&:async_path_uri).then do |path_uri|
      path_uri = path_uri.dup
      path_uri.fragment = "advisory-comment-#{id}"
      path_uri
    end
  end

  def advisory_ghsa_id
    T.must(repository_advisory).ghsa_id
  end

  def repository
    async_repository.sync
  end

  def repository_id
    repository.id
  end

  def async_repository
    async_repository_advisory.then(&:async_repository)
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # GitHub::MinimizeComment interface.
  def minimized?
    false
  end

  def async_viewer_can_read_user_content_edits?(viewer)
    async_repository_advisory.then do |advisory|
      advisory.async_writable_by?(viewer)
    end
  end

  def viewer_can_read_user_content_edits?(viewer)
    return @viewer_can_read_user_content_edits if defined? @viewer_can_read_user_content_edits
    @viewer_can_read_user_content_edits = async_viewer_can_read_user_content_edits?(viewer).sync
  end

  def readable_by?(viewer)
    async_readable_by?(viewer).sync
  end

  def async_readable_by?(viewer)
    async_repository_advisory.then do |advisory|
      advisory.async_writable_by?(viewer).then do |advisory_writable|
        # If the viewer is an advisory collaborator, they can see any comment.
        next true if advisory_writable

        advisory.async_readable_by?(viewer).then do |advisory_readable|
          # If the viewer is not an advisory collaborator, they must at the very
          # least be able to read the advisory.
          next false unless advisory_readable

          # At this point, we know the viewer is not an advisory collaborator
          # but can read the advisory. Now we only need to check that the
          # comment is not considered internal.
          async_internal?.then { |internal| !internal }
        end
      end
    end
  end

  def async_target_for_conditional_access
    async_repository.then(&:async_target_for_conditional_access)
  end

  def async_viewer_can_delete?(viewer)
    async_viewer_can_update?(viewer)
  end

  def viewer_can_delete?(user = nil)
    return @viewer_can_delete if defined?(@viewer_can_delete)
    return false if user.nil?

    @viewer_can_delete = async_viewer_can_delete?(user).sync
  end

  def viewer_can_update?(user = nil)
    # this does not support multiple viewers currently
    return @viewer_can_update if defined? @viewer_can_update
    return false if user.nil?

    @viewer_can_update = async_viewer_can_update?(user).sync
  end

  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_update_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    async_user.then do |user|
      # Only allow staff to update or delete comments by the special staff user.
      next [:insufficient_access] if user&.staff_user? && !viewer.site_admin?

      # Regular collaborators can only update their own comments
      next [] if user == viewer

      # Maintainers can update all comments, except staff user's.
      async_repository_advisory.then do |advisory|
        advisory.async_adminable_by?(viewer).then do |advisory_adminable|
          advisory_adminable ? [] : [:insufficient_access]
        end
      end
    end
  end

  def async_internal?
    async_after_publication?.then do |after_publication|
      # All pre-publication comments are considered internal.
      next true unless after_publication

      # Even some comments that are posted after publication are considered
      # internal, like those authored by the special staff user regarding the
      # maintainers' CVE request.
      #
      # See: https://github.com/github/team-advisory-database/issues/826
      async_user.then do |user|
        user ? user.staff_user? : false
      end
    end
  end

  def preload_viewer_attributes(viewer, repo)
    viewer_data = Promise.all(
      [
        async_viewer_can_delete?(viewer),
        async_viewer_can_update?(viewer),
        async_viewer_can_report?(viewer),
        async_viewer_can_block_from_org?(viewer),
        async_viewer_can_unblock_from_org?(viewer),
        async_viewer_relationship(viewer),
      ]
    ).sync

    @viewer_can_delete,
    @viewer_can_update,
    @viewer_can_report,
    @viewer_can_block_from_org,
    @viewer_can_unblock_from_org,
    @viewer_relationship = viewer_data
  end

  def internal?
    async_internal?.sync
  end

  # Notifications

  def message_id
    "<#{repository.name_with_display_owner}/repository-advisories/#{T.must(repository_advisory).id}/comments/#{id}@#{GitHub.urls.host_name}>"
  end

  def get_notification_summary
    T.must(repository_advisory).get_notification_summary
  end

  def notifications_thread
    repository_advisory
  end

  def notifications_author
    user
  end

  def async_notifications_list
    async_repository
  end

  def async_organization
    async_repository.then(&:async_organization)
  end

  def async_entity
    async_repository
  end

  def entity
    repository
  end

  def permalink(include_host: true)
    "#{T.must(repository_advisory).permalink(include_host: include_host)}#advisory-comment-#{id}"
  end
  alias url permalink

  def unsubscribable_users(users)
    T.must(repository_advisory).unsubscribable_users(users)
  end

  def author_subscribe_reason
    "comment"
  end

  def mentioned_users
    users = super
    writable_user_ids = T.must(repository_advisory).actor_ids(type: User, min_action: :write, actor_ids_filter: users.pluck(:id))

    users & User.where(id: writable_user_ids)
  end

  def deliver_notifications(event_time: nil)
    # Send a notification directly to those mentioned. Avoid triggering if empty to prevent sending notifications through
    # newsies default subscriptions.
    mentioned_user_ids = deliverable_direct_mention_user_ids(mentioned_users.map(&:id), T.must(user).id) || []
    GitHub.newsies.trigger(
      self,
      event_time: event_time || created_at,
      recipient_ids: mentioned_user_ids,
      reason: "mention",
    ) if mentioned_user_ids.present?

    # Send "comment" notifications to all other users.
    all_other_user_ids = deliverable_user_ids(comment_author_id: T.must(user).id) - mentioned_user_ids
    GitHub.newsies.trigger(self, event_time: event_time || created_at, recipient_ids: all_other_user_ids, reason: "comment") if all_other_user_ids.present?
    true
  end

  private

  def author_must_have_write_permission
    # The special staff user is allowed to author comments on the advisory
    # timeline without have access to the advisory itself.
    return if user&.staff_user?

    if repository_advisory.present? && !T.must(repository_advisory).writable_by?(user)
      errors.add(:user, "must have write permission")
    end
  end

  def cannot_be_created_after_advisory_publication
    if repository_advisory&.published?
      errors.add(:base, "The advisory has been published, so comments are closed.")
    end
  end
end
