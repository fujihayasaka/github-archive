# typed: true
# frozen_string_literal: true

class OrganizationDiscussionPost < ApplicationRecord::Collab # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  belongs_to :user
  belongs_to :pinned_by, class_name: "User", foreign_key: "pinned_by_user_id" # rubocop:todo Rails/InverseOf
  belongs_to :organization

  include OrganizationDiscussionItem
  include Spam::ContentUserIsSpammy

  has_many :replies, class_name: "OrganizationDiscussionPostReply"
  destroy_dependents_in_background :replies

  attr_readonly :number

  before_create :set_number

  # Use VARBINARY limit from the database
  TITLE_BYTESIZE_LIMIT = 1024

  attribute :title, StringFromBinary.new

  validates :title, bytesize: { maximum: TITLE_BYTESIZE_LIMIT }, unicode: true

  scope :public_posts, -> { where(private: false) }

  scope :visible_to, ->(user) do
    if user
      org_ids = User::OrganizationFilter.new(user).unscoped_ids
      public_posts.or(where(organization_id: org_ids))
    else
      public_posts
    end
  end

  scope :most_recent, -> { order(id: :desc) }

  # Implements a required property of the Platform::Interfaces::Comment.
  #
  # You cannot create a discussion by email.
  sig { returns T::Boolean }
  def created_via_email
    false
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_viewer_can_pin?(viewer)
    async_organization.then { |org| T.must(org).async_adminable_by?(viewer) }
  end

  sig { override.params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_readable_by?(viewer)
    if public?
      Promise.resolve(true)
    else
      async_organization.then { |org| T.must(org).member_or_can_view_members?(viewer) }
    end
  end

  sig { returns T::Boolean }
  def title_changed?
    self.title.try(&:b) != self.title_was.try(&:b)
  end

  sig { params(user_id: Integer).void }
  def pin_by(user_id:)
    self.pinned_at = Time.current
    self.pinned_by_user_id = user_id
  end

  sig { void }
  def unpin
    self.pinned_at = nil
    self.pinned_by_user_id = nil
  end

  sig { returns T::Boolean }
  def pinned?
    !pinned_at.nil?
  end

  sig { returns T::Boolean }
  def public?
    !private?
  end

  sig { override.params(actor: T.any(IntegrationInstallation, Bot)).returns(Promise[T::Boolean]) }
  def async_is_programmatic_actor_with_write_access?(actor)
    async_is_programmatic_actor_with_access?(actor, :write)
  end

  sig { returns String }
  def platform_type_name
    "OrganizationDiscussion"
  end

  private

  # Does the given actor have access to org discussions?
  #
  # actor - Either an IntegrationInstallation or a Bot. Bots can only write
  #         public discussions, but IntegrationInstallations can write both
  #         public and private discussions. This is safe because an
  #         IntegrationInstallation can never act on its own, so ultimately this
  #         will get called again with the installation's bot user or the human
  #         user on behalf of whom the installation is acting.
  #
  # action - Symbol representing the desired access level (:read or :write).
  #
  # Returns a Promise of a Boolean.
  sig { params(actor: T.any(IntegrationInstallation, Bot), action: Symbol).returns(Promise[T::Boolean]) }
  def async_is_programmatic_actor_with_access?(actor, action)
    unless actor.can_have_granular_permissions?
      return Promise.resolve(T.let(false, T::Boolean))
    end

    async_organization.then do |org|
      if action == :read
        T.must(org).resources.team_discussions.async_readable_by?(actor)
      elsif action == :write
        T.must(org).resources.team_discussions.async_writable_by?(actor)
      end
    end
  end

  sig { void }
  def set_number
    organization = self.organization
    if organization && !Sequence.exists?(organization)
      Sequence.create(organization, organization.discussion_posts.count)
    end
    self.number = Sequence.next(organization)
  end
end
