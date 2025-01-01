# typed: false
# frozen_string_literal: true

class GistComment < ApplicationRecord::Domain::Gists
  include GitHub::UTF8
  include GitHub::UserContent
  include GitHub::MinimizeComment
  include Spam::Spammable
  include EmailReceivable
  include UserContentEditable
  include AuthorAssociable
  include Instrumentation::Model
  include GitHub::RateLimitedCreation
  include NotificationsContent::WithCallbacks
  include GistComment::NewsiesAdapter
  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::GistComment


  COMMENT_MAX_LENGTH = 65535

  belongs_to :gist, inverse_of: :comments,  touch: true
  belongs_to :user

  setup_spammable(:user)

  validates_presence_of :gist, :user, :body
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true
  validate :ensure_not_blocked_by_author, on: [:create, :update]

  after_commit :enqueue_check_for_spam

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update, if: :body_changed_after_commit?
  after_commit :subscribe_and_notify, on: :create
  after_commit :update_subscriptions_and_notify, on: :update
  after_commit :instrument_destruction, on: :destroy

  delegate :target_for_conditional_access, to: :gist

  scope :public_scope, -> { joins(:gist).where("gists.public = ?", true) }

  attribute :body, StringFromBinary.new

  enum :comment_hidden_by, GitHub::MinimizeComment::ROLES

  # Override reading the body to guarantee returning valid utf8 encoded data.
  #
  # See also GitHub::UTF8
  def body
    utf8(read_attribute(:body))
  end

  def async_performed_via_integration
    Promise.resolve(nil)
  end

  def last_modified_at
    @last_modified_at ||= last_modified_with :user
  end

  def global_id
    self.async_gist.sync # TODO(nick): Make to_global_id resolve promises instead of this
    "#{gist.repo_name}:#{id}"
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_gist.then do |gist|
      path_uri = gist.path_uri.dup
      path_uri.fragment = anchor
      path_uri
    end
  end

  def comment_path_url
    url_prefix = if GitHub.gist3_domain?
      ""
    else
      "/gist"
    end

    "#{url_prefix}/#{gist.name_with_owner}/comments/#{id}"
  end

  def permalink_url
    url_prefix = if GitHub.gist3_domain?
      ""
    else
      "/gist"
    end

    "#{url_prefix}/#{gist.name_with_owner}?permalink_comment_id=#{id}##{anchor}"
  end

  def absolute_permalink_url
    "#{GitHub.gist_url}/#{permalink_url}"
  end

  def anchor
    "gistcomment-#{id}"
  end

  def subject_gid
    gist.global_relay_id
  end

  def to_hash
    {
      id: id,
      body: body,
      user: user.to_s,
      gravatar_id: "",
      created_at: created_at,
      updated_at: updated_at,
    }
  end

  def check_for_spam(options = {})
    if reason = GitHub::SpamChecker.test_comment(self)
      GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:gist_comment"]
      user.safer_mark_as_spammy(reason: "Gist comment spam (#{reason})")
    end

    # Allow the comment to be posted in case we made a mistake and
    # need to recover it later.
    true
  end

  def async_readable_by?(user)
    async_gist.then do |gist|
      gist.async_readable_by?(user)
    end
  end

  def readable_by?(user)
    async_readable_by?(user).sync
  end

  # Who can edit/delete this comment?
  def async_adminable_by?(admin_user)
    return Promise.resolve(false) unless admin_user.present?

    async_gist.then do |gist|
      gist.async_adminable_by?(admin_user).then do |adminable|
        # Staff, and Gist creator
        next true if adminable
        async_user.then { |user| user == admin_user }
      end
    end
  end

  def adminable_by?(admin_user)
    async_adminable_by?(admin_user).sync
  end

  def async_minimizable_by?(viewer)
    return Promise.resolve(false) unless viewer.present?
    return Promise.resolve(true) if viewer.site_admin?

    # Users can always minimize their own comments
    return Promise.resolve(true) if user_id == viewer.id

    async_gist.then do |gist|
      # Staff, and Gist creator
      gist.async_adminable_by?(viewer)
    end
  end

  def async_unminimizable_by?(actor)
    return Promise.resolve(false) unless actor.present?
    return Promise.resolve(true) if actor.site_admin?


    async_gist.then do |gist|
      next false unless gist

      gist.async_adminable_by?(actor).then do |is_pushable|
        next is_pushable if minimized_by_maintainer?
        next false unless minimized_by_author?

        is_pushable || actor.id == user_id
      end
    end
  end

  # If a user is blocked, prevent them from commenting on Gists
  # Users can't be blocked from anonymous gists
  #
  # Returns a boolean
  def author_blocking?(other_user)
    return false if modifying_user && modifying_user.site_admin?
    author = User.find_by_login(gist.user_param)
    commenter = User.find_by_login(other_user)

    return false unless author && commenter
    author.blocking?(commenter)
  end

  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer
    return Promise.resolve(true) if viewer.site_admin?

    async_viewer_can_update?(viewer)
  end

  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_update_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    Promise.all([async_gist.then(&:async_user), async_user]).then do |_gist, _user|
      if !adminable_by?(viewer)
        [:insufficient_access]
      else
        []
      end
    end
  end

  def event_payload
    {
      author: self.user,
      gist_comment: self,
      body: body,
    }
  end

  def async_target_for_conditional_access
    async_gist.then(&:async_target_for_conditional_access)
  end

  # Gist comments don't support reactions, so we return false for all users
  def prelude_viewer_can_react(user)
    false
  end

  # Gist comments don't track reports in the db, so we stub out report-tracking
  # methods
  def report_count
    nil
  end

  def async_viewer_can_report?(viewer)
    can_report = GitHub.user_abuse_mitigation_enabled? && viewer.id != user&.id
    Promise.resolve(can_report)
  end

  private

  def instrument_creation
    instrument :create
    GlobalInstrumenter.instrument("gist_comment.create", { gist_comment: self, actor: self.user })
  end

  def instrument_update
    previous_body = previous_changes[:body].try(:first)
    instrument :update, old_body: previous_body
    GlobalInstrumenter.instrument("gist_comment.update", { gist_comment: self, previous_body: previous_body, actor: self.user })
  end

  def instrument_destruction
    instrument :destroy
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the user which we know exists.
  def modifying_user
    @modifying_user ||= (User.find_by_id(GitHub.context[:actor_id]) || user)
  end

  def body_changed_after_commit?
    previous_changes.key?(:body)
  end

  # Internal.
  def max_textile_id
    GitHub.max_textile_gist_comment_id
  end

  def ensure_not_blocked_by_author
    errors.add(:user, "is blocked") if author_blocking?(user)
  end
end
