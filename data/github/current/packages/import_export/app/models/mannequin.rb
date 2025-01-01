# typed: true
# frozen_string_literal: true

##
# Mannequin
#
# Mannequins are models that look like users, but aren't users at all! They're
# used to attribute data that gets imported to GitHub using GitHub::Migrator
# when that data has no existing user that it can be attributed to. We use
# this model to buy back some fidelity and show helpful context such as a
# display name.
class Mannequin < User
  before_validation :set_login!, on: :create
  before_validation :scrub_profile_name, on: :update

  has_one :mannequin_ownership
  has_one :owner, through: :mannequin_ownership, required: true

  has_one :mannequin_claim
  has_one :claimant, through: :mannequin_claim, required: false

  before_validation :set_business_id_if_multi_tenant

  before_validation :truncate_source_login!, on: :create
  validates_presence_of :source_login
  validates_length_of :source_login, within: 1..User::LOGIN_MAX_LENGTH

  has_many :emails, dependent: :delete_all, class_name: "MannequinEmail"

  # This is required due to the nonstandard way we do STI and polymorphism
  # between User, Organization, Mannequin, and Project. For more context, check
  # out Project#ensure_correct_owner_type, and Organization's `has_many
  # :projects` line. Once those are made standard, this can be removed.
  # rubocop:todo Rails/InverseOf
  has_many :projects, -> { where(owner_type: "Mannequin") },
    foreign_key: :owner_id
  # rubocop:enable Rails/InverseOf

  scope :query, ->(query) { left_outer_joins(:emails).where("users.source_login LIKE :query OR mannequin_emails.email LIKE :query", query: "%#{query}%") }

  attribute :login, :string

  def name
    return profile_name if profile_name

    sanitized_source_login
  end

  def to_s
    sanitized_source_login
  end

  def safe_profile_name
    profile_name.blank? ? login : profile_name
  end

  def display_login_legacy
    sanitized_source_login
  end

  # The db value of display_login is ignored for mannequins since mannequins use soruce_login (the user readable value) as display_login instead of the guid login value
  # Refer https://github.com/github/external-identities/issues/3238
  def display_login
    display_login_legacy
  end

  # Login for APIs is always login for mannequins; Octoshift CI relies on public APIs to lookup mannequins by login
  def login_for_api(use: :unique)
    login
  end

  # Mannequins don't have passwords - you can't log in as them.
  def password_validation_required?
    false
  end

  def email_address_required?
    false
  end

  def must_verify_email?
    false
  end

  def receives_confirmation_when_destroyed?
    false
  end

  # Public: A Mannequin can never be authenticated by a password.
  #
  # Returns false
  def authenticated_by_password?(password = nil)
    GitHub.dogstats.increment("user", tags: ["action:mannequin_login_attempt"])
    false
  end

  def path
    "#"
  end

  def mannequin?
    true
  end

  def user?
    false
  end

  def anonymous_user_email
    StealthEmail.new(self).email
  end

  def organization?
    false
  end

  def bot?
    false
  end

  def is_enterprise_managed?
    false
  end

  # A Mannequin shouldn't be granted any permissions ever
  def can_be_granted_abilities?
    false
  end

  def organizations
    Organization.where(id: owner&.id)
  end

  # This overrides User#instrument_user_signup so that Mannequins don't
  # publish user.signup hydro events.
  #
  # Returns nothing.

  def instrument_user_signup
    # no=op
  end

  def add_email(email, options = {})
    self.emails.build(email: email)

    save
  end

  def email
    @email ||= emails.last.try(:email)
  end

  def uniqueness_of_email
    # Mannequins don't care about uniqueness of email, so this validation
    # method inherited from User can be a no-op.
  end

  def never_spammy?
    true
  end

  def claimant_login
    claimant&.display_login
  end

  # If source_login is shaped like an email address, only return the portion
  # before the "@"
  def sanitized_source_login
    if source_login =~ User::EMAIL_REGEX
      T.must(source_login).gsub(/@.+/, "")
    else
      source_login
    end
  end

  private

  def set_business_id_if_multi_tenant
    return unless GitHub.multi_tenant_enterprise?

    if self.owner&.business&.id.nil?
      self.business_id = T.unsafe(self.owner&.business&.id)
    else
      self.business_id = T.must(self.owner&.business&.id)
    end
  end

  def set_login!
    self.login = SecureRandom.alphanumeric(User::LOGIN_MAX_LENGTH)
  end

  def truncate_source_login!
    return unless self.source_login
    self.source_login = T.must(self.source_login).truncate(User::LOGIN_MAX_LENGTH)
  end

  # If the profile name has any invalid characters (like emojis) above 0xFFFF, remove them and
  # strip and leading/trailing whitespace so that the profile_name's unicode3 validation passes.
  def scrub_profile_name
    self.profile_name = GitHub::UTF8.scrubbed_unicode3(self.profile_name).strip unless self.profile.nil?
  end
end
