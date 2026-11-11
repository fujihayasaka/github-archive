# typed: true
# frozen_string_literal: true

# Shared methods for revoking credential authorizations, PATs, and SSH keys.
# Included by jobs that perform credential revocation at either the enterprise
# or user level.
#
# Requires the including class to provide `with_write` (from ApplicationJob).
module CredentialRevocationMethods
  extend T::Helpers

  requires_ancestor { ApplicationJob }

  # Revoke a single credential authorization (handles both Organization and Business)
  def revoke_single_credential_authorization(auth, actor, revoked_items)
    success = T.let(false, T::Boolean)

    with_write do
      # revoke methods on the cred auth models are not used here because they don't allow GitHub staff
      if auth.update(revoked_by_id: actor.id, revoked_at: Time.current)
        auth.instrument :revoke, actor: actor, owner: auth.actor
        success = true
      end
    end

    # Only record if the revocation was successful
    return unless success

    if auth.is_a?(Organization::CredentialAuthorization)
      revoked_items[:organization_credential_authorizations] += 1
    else
      revoked_items[:enterprise_credential_authorizations] += 1
    end
  end

  # Revoke all classic personal access tokens (PAT v1) for multiple users in bulk
  def revoke_classic_pats_in_bulk(user_ids, actor, revoked_items)
    explanation = actor.site_admin? ? :site_admin : :enterprise_admin

    # Query all classic PATs for this batch of users
    tokens = OauthAccessTokens.domain.by_users_and_application(
      user_ids,
      OauthApplication::PERSONAL_TOKENS_APPLICATION_ID,
      OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE
    )

    tokens.each do |token|
      result = T.let(nil, T.nilable(GH::Result[T::Boolean]))
      with_write do
        result = OauthAccessTokens.domain.destroy(token.id, explanation, entry_point: job_entry_point)
      end

      # Only record if the destroy was successful
      revoked_items[:classic_pats] += 1 if result&.ok?
    end
  end

  # Revoke all fine-grained personal access tokens (PAT v2) for multiple users in bulk
  def revoke_fine_grained_pats_in_bulk(user_ids, actor, revoked_items)
    explanation = actor.site_admin? ? :site_admin : :enterprise_admin

    # Query all fine-grained PATs for this batch of users
    UserProgrammaticAccess
      .where(user_id: user_ids)
      .find_each do |access|
        result = T.let(nil, T.nilable(ProgrammaticAccessTokens::IResult))
        with_write do
          result = ProgrammaticAccess.destroy(access, explanation)
        end

        # Only record if the destroy was successful
        revoked_items[:fine_grained_pats] += 1 if result&.success?
      end
  end

  # Revoke all SSH keys for multiple users in bulk
  def revoke_ssh_keys_in_bulk(user_ids, actor, revoked_items)
    explanation = actor.site_admin? ? :removed_by_staff : :enterprise_admin

    # Query all SSH keys for this batch of users
    PublicKey
      .where(user_id: user_ids)
      .find_each do |key|
        destroyed = T.let(nil, T.untyped)
        with_write do
          destroyed = key.destroy_with_explanation(explanation)
        end

        # Only record if the destroy was successful
        revoked_items[:ssh_keys] += 1 if destroyed
      end
  end

  private

  # Derive entry point symbol from the including job's class name
  def job_entry_point
    T.must(self.class.name).underscore.to_sym
  end
end
