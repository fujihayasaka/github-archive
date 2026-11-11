# typed: false
# frozen_string_literal: true

class EmailRole < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  class CannotDeleteLastPrimaryEmail < RuntimeError; end
  class CannotDeletePrimaryWithoutAlternate < RuntimeError; end
  Roles = %w[primary backup stealth hard_bounce suppressed]
  belongs_to :user
  belongs_to :email, class_name: "UserEmail"
  after_create_commit   :instrument_creation
  before_destroy :prevent_last_primary_email_deletion,  if: :primary?
  before_destroy :enqueue_sendgrid_suppression_removal, if: :hard_bounce?

  scope :with_roles, ->(*roles) { where(role: roles) }
  scope :primary, -> { with_roles("primary") }
  scope :backup, -> { with_roles("backup") }
  scope :suppressed, -> { with_roles("suppressed") }
  scope :stealth, -> { with_roles("stealth") }
  scope :most_recent_email_first, -> { order(email_id: :desc) }

  delegate :no_existing_email_roles?, to: :user

  validates_presence_of :role
  validates_inclusion_of :role, in: Roles
  validates :role, uniqueness: { scope: :email_id, case_sensitive: false }, unless: :no_existing_email_roles?
  validate :ensure_only_one_primary, if: :primary?
  validate :ensure_only_one_backup, if: :backup?

  # Beware, this is overriding the built-in `public` method.
  # Example of what can go wrong: https://github.com/github/dependency-graph-api/pull/2557
  def self.public
    where(public: true)
  end

  # Public: define query methods for all the valid roles
  #
  # Return Boolean
  Roles.each do |role_name|
    define_method("#{role_name}?") do
      role == role_name
    end
  end

  # Public: Should the related email be "visible" to the outside world?
  def visibility
    public? ? "public" : "private"
  end

  def private?
    !public?
  end

  # Public: toggle the visibility of this email
  def toggle_visibility
    update!(public: !self.public?)
  end

  private

  # Internal: validate that a User can only have one primary email
  def ensure_only_one_primary
    return true if user.primary_user_email_role.nil?
    other_primary_roles = user.email_roles.primary - [self]
    if other_primary_roles.any?
      self.errors.add(:base, "Cannot assign multiple primary emails")
    end
  end

  # Internal: validate that a User can only have one backup email
  def ensure_only_one_backup
    return true if user.backup_user_email_role.nil?
    other_backup_roles = user.email_roles.backup - [self]
    if other_backup_roles.any?
      self.errors.add(:base, "Cannot assign multiple backup emails")
    end
  end

  # Internal: Prevent removal of a primary email
  # if it's the User's only email.
  def prevent_last_primary_email_deletion
    if primary? && email.last_email?
      raise CannotDeleteLastPrimaryEmail
    end
  end

  # Internal: event payload for Instrumentation
  def event_payload
    {
      email_role: role,
      email_role_id: id,
      email: email.email,
      email_id: email.id,
      user: email.user,
    }
  end

  # Internal: instrument creation of an EmailRole
  def instrument_creation
    instrument :create, event_payload
  end

  def enqueue_sendgrid_suppression_removal
    if GitHub.sendgrid_enabled?
      SendgridSuppressionRemovalJob.perform_later(email.id)
    end
  end
end
