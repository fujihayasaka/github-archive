# typed: false
# frozen_string_literal: true

class ExternalIdentitySession < ApplicationRecord::Domain::Users
  belongs_to :user_session
  belongs_to :external_identity

  delegate :target, to: :external_identity
  delegate :user_id, to: :user_session

  validates :user_session, presence: true
  validates :external_identity, presence: true
  validates :expires_at, presence: true

  before_validation :set_default_expiration

  scope :active,  -> { where("external_identity_sessions.expires_at > ?", Time.now) }
  scope :expired, -> { where("external_identity_sessions.expires_at <= ?", Time.now) }

  # Used by `UserSession` to find the active session for a specific identity.
  scope :by_identity, -> (identity) { where(external_identity_id: identity.id) }

  scope :by_sso_provider, -> (provider) { joins(:external_identity).
    where(external_identities: {  provider_id: provider.id, provider_type: provider.class.name  })
  }

  scope :by_user_session, -> (user_session) { where(user_session_id: user_session.id) }

  scope :with_user_session, -> { includes(:user_session).where.not(user_session: { id: nil }) }

  def destroy
    revoked = on_destroy_revoke_emu_session
    GitHub.dogstats.increment("external_identity_session.destroy.revoke_user_session", tags: ["revoked:#{revoked}"])
    super
  end

  private

  def on_destroy_revoke_emu_session
    # if we're being deleted downstream of the parent user_session, this is unnecessary
    return false if destroyed_by_association

    user = user_session&.user
    return false unless user && user.feature_enabled?(:emu_user_session_expiration)
    return false unless user.is_emu_and_not_first_owner?

    user_session.revoke(:emu_session_revoked)
    true
  end

  def set_default_expiration
    self.expires_at ||= 1.day.from_now
  end
end
