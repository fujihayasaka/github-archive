# typed: strict
# frozen_string_literal: true

# Stores precomputed GHEC higher rate limit eligibility for OAuth app tokens.
#
# Each row represents a (app_id, user_id) pair from the oauth_accesses table,
# along with the computed request_owner_id and whether the token qualifies for
# GHEC higher rate limits. Authnd reads this table during token enrichment.
class OauthEnterpriseLimit < ApplicationRecord::Domain::Authentication
  validates :app_id, presence: true
  validates :user_id, presence: true
  validates :app_id, uniqueness: { scope: :user_id }

  # Upsert a row for the given app/user pair. Only called when the user
  # qualifies for higher rate limits — higher_limit_eligible is always true.
  sig do
    params(
      app_id: Integer,
      user_id: Integer,
      request_owner_id: Integer,
    ).void
  end
  def self.upsert_limit(app_id:, user_id:, request_owner_id:)
    upsert(
      { app_id:, user_id:, request_owner_id:, higher_limit_eligible: true },
    )
  end

  # Remove the row for the given app/user pair.
  sig { params(app_id: Integer, user_id: Integer).void }
  def self.remove_limit(app_id:, user_id:)
    where(app_id:, user_id:).delete_all
  end
end
