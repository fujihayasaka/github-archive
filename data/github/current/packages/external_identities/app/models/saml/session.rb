# typed: false
# frozen_string_literal: true

module SAML
  class Session < ApplicationRecord::Domain::Users
    self.table_name = "saml_sessions"

    belongs_to :user, inverse_of: :saml_session

    validates_uniqueness_of :user_id

    before_save    :log_change
    before_destroy :revoke_on_destroy

    scope :active, -> { where("saml_sessions.expires_at IS NOT NULL AND saml_sessions.expires_at > ?", Time.now) }

    # Public: Returns BatchEnumerator of sessions that are expired
    def self.expired
      SAML::Session.where("expires_at IS NOT NULL AND expires_at < ?", Time.now).in_batches(of: 1000)
    end

    private

    def log_change
      GitHub::Authentication.logger.info("Updating SAML session", "code.namespace" => self.class.name, "code.function" => __method__, "gh.enduser.login" => user.login, "gh.enduser.id" => user.id, "saml.session.expires_at" => expires_at || "No expiration provided")
    end

    # Private: Revoke user's active sessions
    def revoke_on_destroy
      GitHub::Authentication.logger.info("Revoking user sessions", "code.namespace" => self.class.name, "code.function" => __method__, "gh.enduser.login" => user&.login, "gh.enduser.id" => user&.id)
      user.revoke_active_sessions(:saml_expired) if user
    end
  end
end
