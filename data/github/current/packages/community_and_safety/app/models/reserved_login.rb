# typed: false
# frozen_string_literal: true

class ReservedLogin < ApplicationRecord::Ballast
  # Interval after which a tombstone expires and the corresponding login becomes
  # available for registration.
  DEFAULT_TOMBSTONE_EXPIRY = 90.days
  RESTRICTED_KEYWORDS = %w[dependabot github].freeze

  # If a user deletes their account and returns within this period in the same
  # session (ie. same `persistent_client_id` in the `_octo` cookie), we allow
  # them to bypass the tombstone and recreate their account.
  TOMBSTONE_GRACE_PERIOD = 30.minutes

  include Instrumentation::Model

  validates_presence_of :login
  validates_format_of :login, with: User::LOGIN_REGEX
  validates_uniqueness_of :login, message: "has already been reserved", case_sensitive: false

  before_save :already_reserved?

  before_validation :downcase_login
  after_destroy_commit :instrument_destroy
  after_create_commit :instrument_create

  enum :kind, {
    staff_reserved: 0,
    tombstoned: 1,
  }

  class << self
    def reserve!(login)
      staff_reserved.create!(login: login)
    end

    def tombstone!(login)
      return unless GitHub.tombstone_user_logins?
      tombstoned.create!(login: login, expires_at: DEFAULT_TOMBSTONE_EXPIRY.from_now)
    end

    def untombstone!(login)
      tombstoned.find_by(login: login)&.destroy!
    end

    def reserved?(login, persistent_client_id: nil, skip_keyword_check: false)
      reserved_with_reason?(login, persistent_client_id: persistent_client_id, skip_keyword_check: skip_keyword_check)[:reserved]
    end

    def reserved_with_reason?(login, persistent_client_id: nil, skip_keyword_check: false)
      comparable_login = User.to_display_login(login)
      return { reserved: true, reason: :hardcoded } if hardcoded?(comparable_login)

      if !skip_keyword_check && GitHub.reserved_login_keywords_enabled?
        return { reserved: true, reason: :reserved_login_keyword } if contains_restricted_keywords?(comparable_login)
      end

      # As long as `reserved_logins.login` uses the `utf8` and not the `utf8mb4` charset,
      # we need to ensure that we don't put any unsupported characters in the queries.
      # Otherwise this will cause a `ActiveRecord::StatementInvalidError`.
      return { reserved: false, reason: :unspecified } unless GitHub::UTF8.valid_unicode3?(login)

      reserved_login = ReservedLogin.find_by(login: comparable_login.downcase)
      return { reserved: false, reason: :unspecified } unless reserved_login
      return { reserved: true, reason: :staff_reserved } if reserved_login.staff_reserved?

      return { reserved: false, reason: :unspecified } unless GitHub.tombstone_user_logins?
      return { reserved: false, reason: :unspecified } if within_tombstone_grace_period?(login, persistent_client_id)
      return { reserved: true, reason: :tombstoned } if reserved_login.tombstoned? && !reserved_login.tombstone_expired?

      { reserved: false, reason: :unspecified }
    end

    def hardcoded?(login)
      GitHub::DeniedLogins.include? login.downcase
    end

    def contains_restricted_keywords?(login)
      return false if GitHub::AllowedLogins.include? login.downcase

      RESTRICTED_KEYWORDS.any? { |keyword| login.downcase.match?(keyword) }
    end

    def delete_expired_tombstones
      tombstoned.where("expires_at IS NOT NULL AND expires_at <= ?", Time.now).delete_all
    end

    def configure_tombstone_grace_period(login, persistent_client_id)
      unless persistent_client_id.nil?
        Users::Kv.store.set(
          grace_period_key(login),
          persistent_client_id,
          expires: TOMBSTONE_GRACE_PERIOD.from_now
        )
      end
    end

    def within_tombstone_grace_period?(login, persistent_client_id)
      return false if persistent_client_id.nil?
      value = Users::Kv.store.get(grace_period_key(login)).value { nil }
      value == persistent_client_id
    end

    def restricted_login_keywords
      RESTRICTED_KEYWORDS
    end

    private

    def grace_period_key(login)
      "ReservedLogin:#{login.downcase}:persistent_client_id"
    end
  end

  def hardcoded?
    return @hardcoded if defined? @hardcoded
    @hardcoded = ReservedLogin.hardcoded? login
  end

  def tombstone_expired?
    tombstoned? && expires_at && expires_at <= Time.now
  end

  def add_info(reason = nil, user)
    self.reason = reason
    self.user = user
  end

  private

  def downcase_login
    self.login = self.login.dup.downcase if self.login
  end

  def already_reserved?
    errors.add :base, "Login #{login} is invalid" if ReservedLogin.reserved?(login)
  end

  def instrument_create
    if staff_reserved?
      instrument :create, login: login, reason: Audit.context[:reason]
    end
  end

  def instrument_destroy
    instrument :destroy, login: login
  end
end
