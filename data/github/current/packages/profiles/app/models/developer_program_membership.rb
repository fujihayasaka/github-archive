# typed: false
# frozen_string_literal: true

# Membership in the developer program. Can be either a User or an Organization.
class DeveloperProgramMembership < ApplicationRecord::Domain::Users
  include GitHub::Validations
  # The User or Organization registered for the developer program.
  belongs_to :user
  validates_presence_of   :user_id
  validates_uniqueness_of :user_id

  # The User that did the registering. For individuals this will always be equal
  # to user. For Organizations, this is the user in an organization that
  # registered.
  belongs_to :actor, class_name: "User"
  validates_presence_of :actor
  validate :actor_must_be_a_user

  # Public: String primary support email for this vendor.
  # column :support_email
  validates_presence_of :support_email
  validates_length_of   :support_email, within: 3..100
  validates_format_of   :support_email, with: User::EMAIL_REGEX,
    message: "does not look like an email address"

  validates :support_email, unicode3: true

  # Public: String url for vendor's website.
  # column :website
  validates_presence_of :website
  validates :website, unicode3: true

  # Public: Boolean if this membership is active.
  # column :active

  # Public: Boolean if this User would like to display the developer program
  # badge on their profile
  # column :display_badge

  after_create :instrument_metadata_recalculation
  after_destroy :instrument_metadata_recalculation

  # List of names and emails for GitHub Developer Program subscribers.
  #
  # Return an Array of Hashes.
  def self.email_list
    users = Set.new
    where(active: true).joins(:user).includes(:user).map do |membership|
      if membership.user.organization?
        users.merge membership.user.admins
      else
        users << membership.user
      end
    end

    users.map do |user|
      HashWithIndifferentAccess.new \
        email: user.email,
        name: user.safe_profile_name
    end
  end

  def send_welcome_email
    DeveloperProgramMembershipMailer.welcome(actor).deliver_later

    GitHub.dogstats.increment("developer_program_membership", tags: ["action:register"])
  end

  def leave_program
    if update(active: false)
      GitHub.dogstats.increment("developer_program_membership", tags: ["action:leave"])
      instrument_metadata_recalculation
    end
  end

  private

  def actor_must_be_a_user
    unless actor && actor.user?
      errors.add(:actor, "must be a user")
    end
  end

  def instrument_metadata_recalculation
    return if GitHub.enterprise?

    GlobalInstrumenter.instrument(
      "user_metadata.recalculation.trigger",
      {
        actor_id: user.id,
        target_user_id: user.id,
        target_stream_processor: :DEVELOPER_PROGRAM_MEMBERSHIP,
      },
    )
  end
end
