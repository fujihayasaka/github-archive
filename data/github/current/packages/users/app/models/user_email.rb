# typed: false
# frozen_string_literal: true

class UserEmail < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Validations
  include Spam::Spammable
  include GitHub::Relay::GlobalIdentification
  include GitHub::BatchedScope

  GENERIC_DOMAIN_REGEXP = Regexp.union(
    /[@.](example|test|fake|none|vagrant)\.?(com|net|org|vm)?\z/i,
    /[@.]local\.?(host)?\z/i, # catches "joe@localhost", "joe@me.local.host", "joe@host.local"
  )

  TLD_REGEX = /\.[[:word:]-]{2,}\z/

  # Used to match email 'like' addresses that end in a UUID, a common occurance
  # with commits created via a subversion client using our subversion bridge.
  UUID_REGEX = /[\w]{8}(-[\w]{4}){3}-[\w]{12}\z/

  BOT_REGEX = /#{ Regexp.quote Bot::LOGIN_SUFFIX }/

  LAUNCH_CODE_LENGTH = 8

  GENERIC_EMAIL_ERROR = "Email is invalid or already taken"

  GENERIC_DOMAIN_ERROR = "domain could not be verified"

  ENTERPRISE_MANAGED_USER_ERROR = "Modifications to emails are not allowed, " \
                                  "emails are managed through an Identity Provider " \
                                  "for enterprise managed users."

  CLAIMED_EMAIL_SIGNUP_ERROR = "This email is associated with an Enterprise Managed " \
                               "User (EMU) account. Use a different email address " \
                               "or talk to your administrator about how to sign in " \
                               "to your existing EMU account."

  include UserEmail::MarketingDependency
  include UserEmail::DisposableEmailsDependency

  States = %w( unverified verified )
  attr_writer :allow_stealth
  belongs_to :user
  has_many :email_roles, dependent: :destroy, foreign_key: "email_id", inverse_of: :email

  # rubocop:todo Rails/InverseOf
  has_many :integration_installations,
    foreign_key: :contact_email_id
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_one :sponsors_listing,
    foreign_key: :contact_email_id
  # rubocop:enable Rails/InverseOf

  setup_spammable(:user)

  before_validation :strip_spaces
  before_validation :set_default_state
  before_validation :must_end_with_tld_or_uuid, on: :create, unless: -> { GitHub.enterprise? }

  validates_length_of     :email, within: 3..100
  validate :cannot_create_duplicate_emails
  validates_format_of     :email,
    with: User::EMAIL_REGEX,
    message: "does not look like an email address"
  validates :email, unicode3: true
  validates_inclusion_of  :state, in: States
  validate :cannot_add_github_stealth_emails, unless: :allow_stealth?, on: :create
  validate :cannot_add_sanctioned_emails, on: [:create, :update]
  validate :cannot_add_disposable_emails, on: :create
  validate :cannot_verify_disposable_emails, on: :update, if: :state_changed?
  validate :cannot_use_abusive_special_characters

  validate :email_domain_not_reserved, on: :create, unless: :skip_reserved_domain
  attr_accessor :skip_reserved_domain

  validate :no_emu_email_conflict, on: [:create, :update], if: :validate_no_claimed_email?

  before_save :set_deobfuscated_email, if: :will_save_change_to_email?
  before_save :set_normalized_domain, if: :will_save_change_to_email?
  after_create :mark_as_suppressed!, if: :user_suppressed?
  after_commit :enqueue_check_for_spam, if: :persisted?
  after_commit :process_email_domain_for_reputation_data, on: [:create, :destroy]
  after_commit :update_gpg_key_emails, if: :execute_gpg_key_email_update?
  before_destroy :remove_profile_email
  after_create :instrument_disposable_email_created, if: :disposable?
  after_commit :update_verified_emails_global_notice_next
  after_destroy :delete_social_identity
  after_commit :recalculate_bundled_assignment, on: [:destroy]

  scope :unverified, -> { where("state <> ? or state IS NULL", "verified") }
  scope :verified, -> { user_entered_emails.where("state = ?", "verified") }
  scope :visible, -> { includes(:email_roles).where("email_roles.role is null or email_roles.public = true").references(:email_roles) }
  # user_entered_emails excludes any emails GitHub adds for system purposes, such as the stealth email
  scope :user_entered_emails, -> { exclude_roles("stealth") }
  scope :not_bouncing, -> { exclude_roles("hard_bounce") }
  scope :all_bouncing, -> { includes(:email_roles).where("email_roles.role='hard_bounce'").references(:email_roles) }
  # This is the closest thing we have to 'ordered by created_at', since there aren't timestamps on UserEmails
  scope :ordered_by_id, -> { order(:id) }
  scope :include_roles, -> { includes(:email_roles) }
  # Pull primary emails first (emails with other roles or no assigned role will be sorted beneath)
  scope :primary_first, -> { includes(:email_roles).order(Arel.sql(%q{CASE email_roles.role WHEN "primary" THEN "Z" ELSE email_roles.role END DESC})).references(:email_roles) }
  scope :excluding_ids, -> (*email_ids) { where.not(id: email_ids) }
  scope :contactable, -> { user_entered_emails.verified.primary_first }
  scope :primary, -> { joins(:email_roles).merge(EmailRole.primary) }
  scope :backup, -> { joins(:email_roles).merge(EmailRole.backup) }

  # This query had to go a longer way through external_identities
  # since the business_user_accounts table is in a different schema
  # All of the EMU users will be provisioned and will have an external_identity record
  # which will belong to a saml provider attached to a business marked as EMU
  scope :not_enterprise_managed, -> {
    where(<<-SQL)
      NOT EXISTS (SELECT 1 FROM external_identities ei
          INNER JOIN business_saml_providers bsp
          ON  bsp.id = ei.provider_id
          INNER JOIN businesses b
          ON  b.id = bsp.business_id
          AND b.business_type = 1
        WHERE ei.user_id = user_emails.user_id
        AND   ei.provider_type = 'Business::SamlProvider'
        LIMIT 1)
    SQL
  }

  delegate :visibility, :public, :public?, to: :primary_role, allow_nil: true

  attribute :email, StringFromBinary.new
  attribute :deobfuscated_email, StringFromBinary.new

  # Public: Normalizes email address based on known rules for top
  # providers. It downcases, removes sub-addresses, and performs
  # any local-part normalization.
  #
  # Returns a String.
  def self.normalize(address)
    UserEmail::Normalization.new(address).normalized_address
  end

  # Public: Normalizes email addresses of any number of users and emails.
  # It is safe because it rescues normalization errors caused by passing bad
  # email addresses, leaving you with a list of safe email addresses.
  #
  # Returns an Array of Strings.
  def self.safe_bulk_normalize(users: [], emails: [], verified: true, include_private_emails: true)
    user_emails = email_addresses_for(users, verified: verified, include_private_emails: include_private_emails)
    emails = (user_emails + Array.wrap(emails)).map do |email|
      begin
        normalize(email)
      rescue ArgumentError
      end
    end

    emails.compact
  end

  # Internal: Given a list of users returns a single array containing all email
  # addresses belonging to those users.
  #
  # verified - A Boolean indicating if only verified emails should be returned
  # include_private_emails - A Boolean indicating if private emails should be returned
  #
  # Returns an Array of Strings.
  def self.email_addresses_for(users, verified: false, include_private_emails: true)
    return [] unless users
    Array.wrap(users).flat_map do |user|
      scope = user.emails

      if verified
        scope = scope.verified
      end

      unless include_private_emails
        scope = scope.visible
      end

      scope.map(&:email)
    end
  end

  # Public: List of existing email addresses matching the provided email
  #
  # email: String email
  # exclude_id: Optional UserEmail ID to ignore
  #
  # Returns ActiveRecord Relation
  def self.duplicates(email, exclude_id: nil)
    return [] unless GitHub::UTF8.valid_email?(email)
    dupes = self.where(email: email)
    dupes = dupes.where("user_emails.id <> ?", exclude_id) if exclude_id
    dupes
  end

  # Public: is the email a duplicate of any email in the system?
  #
  # email: String email
  #
  # Returns Boolean
  def self.duplicate?(email)
    duplicates(email).any?
  end

  def self.generate_launch_code_verification
    LAUNCH_CODE_LENGTH.times.map { SecureRandom.random_number(10) }.join
  end

  def to_s
    email
  end

  # Public: is this UserEmail a duplicate of any email in the system?
  #
  # Returns Boolean
  def duplicate?
    self.class.duplicates(email, exclude_id: id).any?
  end

  # Internal: find a single email with the specified String role
  #   ...wish we could do this with a scope, but scopes can't return a single record
  def self.with_role(role)
    include_roles.where("email_roles.role" => role).references(:email_roles).first
  end

  # Internal: Returns the Array of emails that can be used for notifications
  #
  #   This is all verified emails if email verification is enabled and the
  #   user has one or more verified emails. Otherwise, this is all user
  #   entered emails.
  def self.notifiable
    if GitHub.email_verification_enabled?
      verified_emails = not_bouncing.user_entered_emails.verified
      verified_emails.any? ? verified_emails : not_bouncing.user_entered_emails
    else
      not_bouncing.user_entered_emails
    end
  end

  # Public: Check if an email is using a generic domain
  #
  # Used to prevent commit blame using terribly generic email addresses. We do
  # this so that the next person who commits as "root@localhost" or
  # "chris@test.com" doesn't turn around and email support asking why some
  # random person named Chris has access and is committing to their repo.
  #
  #   email - a String containing the email address to test
  #
  # Returns true if the email's domain is generic.
  # This check is disabled (and will always return false) on Enterprise
  # unless specifically enabled by an administrator.
  def self.generic_domain?(email)
    return false unless GitHub.email_detect_generic_domains?
    email =~ GENERIC_DOMAIN_REGEXP
  end

  def self.exclude_roles(*roles)
    subquery = EmailRole.with_roles(*roles).select(:email_id).to_sql
    where("#{table_name}.id NOT IN (#{subquery})")
  end

  # Public: finds a UserEmail for verification belonging to `owned_by` or an
  # organization that is `adminable_by?` owner.
  #
  # For UserEmails not associated directly to `owned_by`, checks that:
  #   - the owner of the UserEmail record is an Organization
  #   - owned_by is an Admin of that Organization
  #
  # Returns nil or a UserEmail record
  def self.find_email_for_verification(id, owned_by:)
    email = owned_by.emails.find_by_id(id)
    return email if email

    if (email = find_by_id(id))
      return nil unless email.user.organization?
      return nil unless email.user.adminable_by?(owned_by)
    end
    email
  end

  def cannot_use_abusive_special_characters
    if has_invalid_special_characters?
      errors.add(:email, "has invalid special characters")
    end
  end

  # Check whether the email address has unquoted special characters, which can be used to
  # craft an address to deliver mail to an unexpected address for exploit purposes.
  #
  # Eg. see https://github.com/github/profile/issues/882
  #
  # We specifically don't want to validate according to the strict RFC, and explicitly allow
  # certain unquoted special characters; this is meant to be very targeted around cases that
  # can be abused.
  def has_invalid_special_characters?
    # Strip out sections surrounded by non-escaped double quote characters
    unquoted_part = email.gsub(/\"([^"]|(?<=\\)")*(?<!\\)"/, "")

    # Strip out the domain part
    local_part = unquoted_part.sub(/@[^@]+\Z/, "")

    # Strip valid comments off the beginning/end of the local part
    local_part = local_part.sub(/\A\([^)]+\)/, "")
    local_part = local_part.sub(/\([^)]+\)\Z/, "")

    # This is a pared-down list of special characters that should be invalid unless quoted, we've removed a couple
    # because we specifically test that characters like , and [] are allowed, eg:
    #
    # "John.O'Brien,and+sons@example.com"
    # "simple-ci[bot]@gmail.com"
    return true if local_part.match?(/[\"\(\):;<>@\\]/)

    has_encoded_abusive_character?
  end

  # Test the quoted-printable decoded form of the email - which is ultimately sent over the wire as part of SMTP
  # messages - for suspicious characters that are likely to be SMTP injection attacks.
  def has_encoded_abusive_character?
    decoded = Mail::Encodings.value_decode(email)
    return false if decoded == email

    decoded.match?(/[\u0000<>\(\)\r\n]/)
  end

  def email_domain_not_reserved
    if FeatureFlag.vexi.enabled?(:reserved_domain, user, default: true) && UserEmail::ReservedEmailDomainDependency.is_reserved_domain?(email)
      errors.add(:email,
        :reserved_domain,
        message: UserEmail::ReservedEmailDomainDependency::RESERVED_DOMAIN_NEW_EMAIL_MESSAGE
      )
    end
  end

  # Public: Toggle the visibility of this primary email
  def toggle_visibility
    instrument_toggle_visibility
    transaction do
      primary_role.toggle_visibility
      user.profile.update_attribute(:email, nil) if private? && user.profile
      create_stealth_email_if_needed
      save!
    end
  end

  def remove_profile_email
    return unless user.profile
    if email == user.profile.email
      user.profile.update_attribute(:email, nil)
    end
  end

  # Public: Mark an email as hard bouncing.
  #
  # Hard bounces are permanent, and the email will typically not be reenabled.
  #
  # Returns the EmailRole if successful, nil otherwise
  def mark_as_bouncing!(source: :local, status: nil, reason: nil)
    return if bouncing?
    return if user.user? && user.is_enterprise_managed?

    role = email_roles.create!(role: :hard_bounce, user: user)
    instrument :hard_bounce, source: source, status: status, reason: reason
    unverify!

    role
  end

  # Internal: mark an email as unverified
  def unverify!
    return if user.user? && user.is_enterprise_managed?

    update! state: "unverified", verified_at: nil
    instrument_unverify
  end

  # Public: Mark an email as suppressed.
  #
  # Unsubscribes the email address from our MailChimp
  # list and ensures the email will not be sent any more
  # marketing email.
  #
  # Returns nothing.
  def mark_as_suppressed!
    return if suppressed? || stealth?
    email_roles.create!(role: "suppressed", user: user)

    if GitHub.mailchimp_enabled?
      MailchimpUnsubscribeJob.perform_later(user.id, self.email)
    end
  end

  # Public: Is the user on the suppression list?
  #
  # Returns a Boolean.
  def user_suppressed?
    SuppressionList.includes_user?(user)
  end

  # Internal: Create a stealth email if the current email got marked as 'private' -
  # Delete stealth email if the current email got marked as 'public' and it uses the old stealth format
  # We only do this if there isn't a stealth email already.
  def create_stealth_email_if_needed
    if public?
      user.emails.select { |e| e.role?("stealth") && e.email !~ StealthEmail::STEALTH_EMAIL_REGEX }.each(&:destroy)
    end

    if private? && user.emails.none? { |e| e.role?("stealth") }
      StealthEmail.new(user).save!
    end
  end

  # Internal: should we make this email stealth?
  def allow_stealth?
    @allow_stealth
  end
  private :allow_stealth?

  # Internal: ensure users can't add github stealth emails, whether or not they actually have one
  def cannot_add_github_stealth_emails
    if StealthEmail.stealthy_email?(email)
      errors.add(:email, "cannot add #{email} - use private email address toggle")
    end
  end

  # Ensure users can't add government emails from sanctioned countries.
  def cannot_add_sanctioned_emails
    if ::TradeControls::Domains.sanctioned_email?(email)
      errors.add(:email, :sanctioned_email, message: ::TradeControls::Notices.notice_as_plaintext(:sanctioned_domain_warning))
    end
  end

  # Internal: Ensure users can't add disposable emails.
  def cannot_add_disposable_emails
    if UserEmail::DisposableEmailsDependency.disposable_email?(email)
      errors.add(:email, :disposable_email, message: GENERIC_DOMAIN_ERROR)
    end
  end

  # Internal: strip any whitespace
  def strip_spaces
    self.email = email.strip
  end

  # Public: Does this email have the specified role?
  #
  # role: String name of the EmailRole
  #
  # Returns the EmailRole if found, otherwise nil
  def role?(role)
    email_roles.where(role: role).first
  end

  def primary_role
    role?("primary")
  end

  # Public: Does this email have an EmailRole indicating it is primary?
  def primary_role?
    !!primary_role
  end

  def backup_role
    role?("backup")
  end

  # Public: Does this email have an EmailRole indicating it is backup?
  def backup_role?
    !!backup_role
  end

  def private?
    !public?
  end

  # Public: Does this email have an EmailRole indicating it is either hard bouncing or soft bouncing?
  #
  # Returns the EmailRole if found, or Nil if the email is not bouncing
  def bouncing?
    role?("hard_bounce")
  end
  alias_method :bouncing, :bouncing?

  # Shadow 'primary' from the ActiveRecord with the new implementation
  alias_method :primary?, :primary_role?
  alias_method :primary, :primary_role?

  # Public: Does this email have an EmailRole indicated it is suppressed?
  # Returns a Boolean.
  def suppressed?
    email_roles.suppressed.exists?
  end

  # Public: Does this email have a stealth EmailRole?
  # Returns a Boolean.
  def stealth?
    email_roles.stealth.exists?
  end

  # Public: Is this email the only verified address the user has?
  # Returns a Boolean.
  def only_verified_email?
    user.emails.user_entered_emails.verified.excluding_ids(self).none?
  end

  # Public: Is the email the last user-entered email for the user?
  # Returns a Boolean.
  def last_email?
    user.emails.user_entered_emails.size == 1
  end

  # Internal: set a default state if none exists
  def set_default_state
    return if state?
    self.state = "unverified"
  end

  def verified?
    self.state == "verified"
  end

  def unverified?
    self.state == "unverified"
  end

  def kv_launch_code_key
    "user_email_id.#{id}.launch_code_valid"
  end

  def launch_code_expired?
    !Users::Kv.store.exists(kv_launch_code_key).value! && launch_code_verification?
  end

  def cannot_create_duplicate_emails
    errors.add(:email, "is taken") if duplicate?
  end

  def validate_no_claimed_email?
    !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
  end

  # Validate that the email can be created or claimed
  #
  # Use `requesting: true` to indicate that the email has not been claimed yet and that the user would like to
  # request a claim on the email. Otherwise, this method assumes that the use is in the process of claiming /
  # unclaiming the email and expects the `claim` value to be set.
  #
  # normal github users cannot create an email that is already claimed by an EMU
  # normal github users can create an email that exists on an EMU user if the EMU email is unclaimed
  # social github users cannot create an email that exists on an EMU user if the EMU email is unclaimed
  # normal github users cannot claim emails
  #
  # emu users can create (or be created with) an email that is already claimed by another EMU
  # or exists on a normal github user, but it will be unclaimed
  # emu users cannot claim an email that is already claimed by another EMU
  # emu users cannot claim an email that already exists on a normal github user
  # emu users can claim an email that is not already claimed by another EMU or exists on a normal github user
  def no_emu_email_conflict(requesting: false, include_unclaimed: false)
    return unless user && email

    # only changes to claimed or an email should trigger this validation or if the requesting is true
    # for new records attribute_changed? will be true
    return if !requesting && !attribute_changed?(:claimed) && !attribute_changed?(:email)

    return if email.is_a?(String) && !GitHub::UTF8.valid_unicode3?(email)
    return if StealthEmail.stealthy_email?(email)

    enterprise_managed_user = user.is_enterprise_managed?

    # if being unclaimed by EMU or created/updated for EMU and not claimed then skip validation
    return if enterprise_managed_user && !claimed && !requesting

    # non-EMU users cannot claim emails
    return errors.add(:email, "cannot be verified by users who are not enterprise managed") if !enterprise_managed_user && claimed

    non_shortcode_email = if enterprise_managed_user
      user.remove_shortcode(email)
    else
      email
    end.downcase

    front, back = GitHub::SpamChecker.get_email_parts(non_shortcode_email)

    # If an email is not valid for example just has a '@' split will return nil for both front and back.
    # The email record is going to be invalid so we do not need to finish running this validation
    return unless front && back

    regex_front, regex_back = UserEmail.regex_friendly_email_parts(non_shortcode_email)

    email_claimed = UserEmail.where(deobfuscated_email: UserEmail.deobfuscate(email))
      # Only select records that do not match the current email id
      .filter { |em| em.id != id }
      # select the following conditions
      #  - for non-EMU users: only search for emails owned by EMUs that are claimed and match self.email
      #  - for EMU users: also search for emails owned by non-EMUs that match self.email
      .select do |em|
        current_email = em.email.downcase
        # Check if the other user is an EMU
        other_user_is_emu = em.user&.is_enterprise_managed? || false

        if enterprise_managed_user
          # If current user is EMU, check for conflicts with any user
          current_email.match?(/#{regex_front}\+.+@#{regex_back}/) && (em.claimed || include_unclaimed) || current_email == "#{front}@#{back}"
        else
          # If current user is not EMU, only check for conflicts with EMU users
          other_user_is_emu && current_email.match?(/#{regex_front}\+.+@#{regex_back}/) && (em.claimed || include_unclaimed)
        end
      end.any?

    errors.add(:email, :claimed_email, message: "is already verified by another user") if email_claimed
  end

  # Internal: Does the email end with a Top Level Domain or a UUID (used in
  # subversion commits)?
  #
  # email: email String
  #
  # Returns a boolean.
  def must_end_with_tld_or_uuid
    return if (email =~ TLD_REGEX).present? || (email =~ UUID_REGEX).present?
    errors.add(:email, "does not look like an email address")
  end

  # Internal: Generate token and send verification email, but only if this email
  #           has not already been verified.
  #
  # requested_by - The User who requested this email verification (only for an
  #                organization).
  # redirect     - A String URL to redirect to after verifying this email (only
  #                for an organization).
  #
  # Returns a Boolean.
  def request_verification(requested_by: nil, redirect: nil, invitation_token: nil, repo_invitation_token: nil)
    return false if !valid? || verified? || !try_to_verify?
    set_verification_token!

    # This prevents the reminder email verification mailer from being sent if a user requests the email verification
    # email to be sent
    kv_key = "user_id.#{user_id}.user_signup_followup_job"

    if user.organization?
      AccountMailer.organization_email_verification(self, requested_by: requested_by, redirect: redirect).deliver_later
    else
      Users::Kv.store.set(kv_key, "true", expires: 2.days.from_now)

      if launch_code_verification?
        SignupsMailer.launch_code_verification(self, invitation_token: invitation_token, repo_invitation_token: repo_invitation_token).deliver_later
      else
        SignupsMailer.email_verification(self).deliver_later
      end
    end

    instrument_request_verification
    true
  end

  # Internal: Send a reminder verification email if user did not verify after initial email
  def request_verification_reminder
    return false if !valid? || verified? || !try_to_verify? || user.organization?
    set_verification_token!

    if launch_code_verification?
      SignupsReminderMailer.launch_code_verification(self).deliver_later
    else
      SignupsReminderMailer.email_verification(self).deliver_later
    end

    instrument_request_verification_reminder
    true
  end

  # Internal: Set the verification_token field for this email.
  #
  # Returns nothing.
  def set_verification_token
    token = if launch_code_verification? || (primary? && user)
      Users::Kv.store.set(kv_launch_code_key, "true", expires: 2.hours.from_now)
      self.class.generate_launch_code_verification
    else
      SecureRandom.hex(20)
    end

    self.verification_token = token
  end

  # Internal: Sets the verification token for this email and saves the record.
  #
  # Returns a Boolean.
  def set_verification_token!
    set_verification_token && save!
  end

  # Internal: Clear the verification_token
  def clear_verification_token
    self.verification_token = nil
  end

  # Internal: Check token and verify the email if it matches.
  #
  # token - A String token value to compare to the verification token for this email.
  #
  # Returns a Boolean indicating if the verification succeeded.
  def confirm_verification(token)
    return false unless token
    return false unless verification_token
    return false if launch_code_expired?

    previous_primary_email = user.primary_user_email

    return false unless SecurityUtils.secure_compare(verification_token, token)

    clear_verification_token
    verify!
    set_as_primary if only_verified_email?
    instrument_confirm_verification(previous_primary_email)
    true
  end

  # Internal: Send a claim email to the user.
  def request_claim(requested_by:)
    return false if GitHub.single_or_multi_tenant_enterprise?

    return false unless requested_by&.is_enterprise_managed?
    return false unless requested_by&.id == user.id
    # should not be able to trigger flow for your email if it's already claimed by you
    return false if claimed?
    # manually call validation with special flag to check for conflicting emails
    return false if no_emu_email_conflict(requesting: true)

    self.verification_token = SecureRandom.hex(8)
    return false unless save

    EnterpriseManagedUserMailer.confirm_claim_email(requested_by, self).deliver_later

    true
  end

  def cancel_claim_request(canceler:)
    return false if GitHub.single_or_multi_tenant_enterprise?

    return false if canceler&.id != user.id
    return false unless canceler&.is_enterprise_managed?
    return false if claimed?

    clear_verification_token
    save
  end

  # Internal: Claim the email.
  def confirm_claim(claimer:, token:)
    return false if GitHub.single_or_multi_tenant_enterprise?

    return false if claimer&.id != user.id
    return false unless token && verification_token
    return false unless SecurityUtils.secure_compare(verification_token, token)

    clear_verification_token
    self.claimed = true

    return false unless save

    instrument_confirm_claim

    true
  end

  # Internal: Unclaim the email.
  def mark_as_unclaimed(unclaimer:)
    return false if GitHub.single_or_multi_tenant_enterprise?

    return false if unclaimer&.id != user.id
    return false unless unclaimer.is_enterprise_managed?

    self.claimed = false

    return false unless save

    instrument_mark_as_unclaimed

    true
  end

  # Public: Will we try to verify this email or is it too generic?
  # i.e. "user@domain", "user@domain.local", or "user@disposable-email.biz"
  def try_to_verify?
    return false if disposable? || domain.nil?
    parts = domain.split(".")
    parts.length > 1 && parts.last != "local"
  end

  # Internal: Sets this email as verified
  #
  # Returns nothing.
  def verify!
    mark_as_verified
    self.email_roles.where(role: ["hard_bounce"]).destroy_all
    save!.tap do
      if GitHub.billing_enabled?
        Licensing::BundledLicenseAssignment.where(email: user.remove_shortcode(email)).find_each do |assignment|
          assignment.attempt_to_assign_user_from_business
        end
      end
    end
  end

  def recalculate_bundled_assignment
    if GitHub.billing_enabled? && FeatureFlag.vexi.enabled?(:allow_revoke_for_volume, default: false)
      Licensing::BundledLicenseAssignment.where(email: user.remove_shortcode(email)).find_each do |assignment|
        assignment.manual_match = true
        assignment.manual_match_at = Time.current
        assignment.save
      end
    end
  end

  # Internal: Mark an email as verified.
  #
  # Returns nothing.
  def mark_as_verified
    self.state = "verified"
    self.verified_at = Time.current
  end

  # Internal: Instrument the email verification request.
  #
  # Returns nothing.
  def instrument_request_verification
    GitHub.dogstats.increment "user_email", tags: ["action:verification.request"]
    instrument :request_verification
  end

  # Internal: Instrument the email verification remindeer request.
  #
  # Returns nothing.
  def instrument_request_verification_reminder
    GitHub.dogstats.increment "user_email_reminder", tags: ["action:verification.request.reminder"]
    instrument :request_verification_reminder
  end

  # Internal: Instrument the email verification confirmation.
  #
  # Returns nothing.
  def instrument_confirm_verification(previous_primary_email)
    GitHub.dogstats.increment "user_email", tags: ["action:verification.confirm"]
    instrument :confirm_verification, verified_at: verified_at
    GlobalInstrumenter.instrument "user_email.verify", {
      user: user,
      # Keep actor here so event has same shape as user.add_email, and in case
      # actor could be other than user in another context, such as if we add
      # the ability to verify an email in staff tools
      actor: user,
      previous_primary_email: previous_primary_email,
      current_primary_email: user.primary_user_email,
      verified_email: self,
    }
  end

  # Internal: Instrument email bounces.
  #
  # Returns nothing.
  def instrument_unverify
    GitHub.dogstats.increment "user_email", tags: ["action:verification.unverify"]
    instrument :unverify
  end

  def instrument_toggle_visibility
    if public?
      GitHub.dogstats.increment "user.email.privacy.visibility_toggle.on"
      instrument :toggle_visibility, visibility: "hidden"
    else
      GitHub.dogstats.increment "user.email.privacy.visibility_toggle.off"
      instrument :toggle_visibility, visibility: "visible"
    end
  end

  def instrument_confirm_claim
    GitHub.dogstats.increment "user_email", tags: ["action:claim.confirm"]
    instrument :confirm_claim
  end

  def instrument_mark_as_unclaimed
    GitHub.dogstats.increment "user_email", tags: ["action:unclaim.confirm"]
    instrument :mark_as_unclaimed
  end

  # Internal: Prefix for auditing / instrumentation
  def event_prefix
    :user_email
  end

  def event_context(prefix: :email)
    {
      prefix => email,
      "#{prefix}_id".to_sym => id,
    }
  end

  # Internal: Default attributes for auditing
  def event_payload
    {
      state: state,
      note: email,
      user: user,
      actor: user,
    }.merge(event_context)
  end

  # The email currently gets checked through User#check_for_spam,
  # so just kick that off.
  def enqueue_check_for_spam
    if previous_changes.include?("email") && user && primary?
      CheckForSpamJob.enqueue(user)
    end
  end

  # See EmailDomainReputationRecord for more details.
  def process_email_domain_for_reputation_data
    EmailDomainReputationRecord.process_later(normalized_domain)
  end

  def self.regex_friendly_email_parts(email)
    return "" unless email.present?

    mailbox, domain = GitHub::SpamChecker.get_email_parts(email)

    mailbox = Regexp.escape(mailbox) if mailbox.present?
    domain = Regexp.escape(domain) if domain.present?

    [mailbox, domain]
  end

  def self.deobfuscate(email)
    return "" unless email.present?

    mailbox, domain = GitHub::SpamChecker.get_email_parts(email)

    # r.a.l.ph@gmail.com or r.a.l-p-h@gmail.com
    mailbox.tr! ".-", ""

    # ralph+1234ed1@gmail.com
    if mailbox =~ /(\w+)\+.*/
      mailbox = Regexp.last_match(1)
    end

    [mailbox, domain].compact.join("@")
  end

  def set_deobfuscated_email
    self.deobfuscated_email = UserEmail.deobfuscate(email)
    true               # Let's just make sure we don't stop the show here
  end

  def set_normalized_domain
    self.normalized_domain = VerifiableDomain.normalize_domain(domain)
  end

  # Is this email a valid education email address
  def education?
    GitHub::EducationEmail.probably_valid? email
  end

  # Update any associated GpgKeyEmails.
  #
  # Returns nothing.
  def update_gpg_key_emails
    # TODO Are emails immutable? Can remove this if so.
    if old_email = previous_changes["email"].try(:first)
      old_email = old_email.split("+#{user.enterprise_managed_business.shortcode}").join if user.is_enterprise_managed?

      GpgKeyEmail.connection.update(Arel.sql(<<-SQL, uid: user_id, email: old_email))
        UPDATE gpg_key_emails
        INNER JOIN gpg_keys ON gpg_key_emails.gpg_key_id = gpg_keys.id
        SET user_email_id = NULL
        WHERE gpg_keys.user_id = :uid
        AND gpg_key_emails.email = :email
      SQL
    end

    value = destroyed? ? nil : self.id
    new_email = email
    new_email = self.email.split("+#{user.enterprise_managed_business.shortcode}").join if user.is_enterprise_managed? && user.enterprise_managed_business.present?
    GpgKeyEmail.connection.update(Arel.sql(<<-SQL, value: value, uid: user_id, email: new_email))
      UPDATE gpg_key_emails
      INNER JOIN gpg_keys ON gpg_key_emails.gpg_key_id = gpg_keys.id
      SET user_email_id = :value
      WHERE gpg_keys.user_id = :uid
      AND gpg_key_emails.email = :email
    SQL
  end

  # The email address's domain
  def domain
    return @domain if defined? @domain
    _, domain = GitHub::SpamChecker.get_email_parts(email)
    @domain = domain ? domain.downcase : nil
  end

  # Public: Check if an email has been generated for a Bot.
  #
  # Used to identity a commit author's email address as coming from an Integration's Bot.
  #
  #   email - a String containing the email address to test
  #
  # Returns true if the email has been generated for a Bot.
  def self.belongs_to_a_bot?(email)
    BOT_REGEX.match?(email) && StealthEmail.stealthy_email?(email)
  end

  # Public: Get a hash of users mapped to the email addresses on the given domains.
  #
  # Note: Only returns verified email addresses if email verification is enabled
  # (GitHub.email_verification_enabled? returns true). If it's disabled, and user emails
  # cannot be verified in the current environment, the check for whether a user email is verified
  # is bypassed and all domain emails for a user are returned.
  #
  # domains - domain url's to get emails for
  # user_ids - list of user_ids for whom to retrieve email addresses
  #
  # Returns: Hash { user_id => [UserEmail] }
  def self.email_addresses_from_domains(domains, user_ids)
    results = if domains.any?
      scope = UserEmail.joins(
        "LEFT JOIN email_roles " \
          "ON user_emails.id = email_roles.email_id " \
          "AND email_roles.role IN ('hard_bounce', 'stealth')",
      ).where(
        email_roles: { id: nil },
        user_id: user_ids,
        normalized_domain: domains,
      )
      scope = scope.where(state: "verified") if GitHub.email_verification_enabled?
      scope.group_by(&:user_id)
    else
      {}
    end

    user_ids.each_with_object(results) do |user_id, result|
      result[user_id] ||= []
    end
  end

  # Public:  Indicates if this user should be receive 6 digit launch code
  # to verify their email as part of signup instead of
  # the traditional verification token
  #
  # We should not be sending launch codes to emails that bounce.
  # https://github.com/github/communities-nux/issues/147
  # Returns a Boolean.
  def launch_code_verification?
    return false if bouncing?
    return false unless verification_token.present?

    # As part of resolving https://github.com/github/github/issues/191964, we increased the length
    # of launch codes from 6 digits to 8 digits. By using <=, this will return true if the email
    # has a launch code that is the old length (because the user signed up before this change) or
    # if the email has a launch code that is the new length. Launch codes expire after 2 hours,
    # so we can change <= to == 2 hours after this change deploys or later.
    verification_token.length <= LAUNCH_CODE_LENGTH
  end

  # Public: Deletes social identities associated with the user email.
  def delete_social_identity
    return unless user.feature_flag_enabled?(:social_cleanup, default: false)
    DeleteSocialIdentityJob.perform_later(user.id, self.id)
  end

  private

  def execute_gpg_key_email_update?
    user.gpg_keys.any?
  end

  def set_as_primary
    user.set_primary_email!(self)
  end

  def update_verified_emails_global_notice_next
    if user.show_verification_reminder?
      GlobalNoticeNext.new(viewer: user).set_notice(:verified_emails)
    end
  end

  # Centralized errors for email validation scenarios
  VALIDATION_ERRORS = {
    sanctioned_email: ::TradeControls::Notices.notice_as_plaintext(:sanctioned_domain_email_warning),
    enterprise_managed: ENTERPRISE_MANAGED_USER_ERROR,
    disposable_email: GENERIC_DOMAIN_ERROR,
    reserved_domain: ReservedEmailDomainDependency::RESERVED_DOMAIN_NEW_ACCOUNT_MESSAGE,
    taken: "The email you have provided is already associated with an account.",
    claimed_email: CLAIMED_EMAIL_SIGNUP_ERROR,
    invalid: GENERIC_EMAIL_ERROR,
    generic_domain: GENERIC_DOMAIN_ERROR
  }.freeze
end
