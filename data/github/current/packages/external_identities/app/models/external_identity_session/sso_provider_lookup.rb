# typed: false
# frozen_string_literal: true

# Permanent helper for querying ExternalIdentitySessions by SSO provider
# without cross-cluster JOINs. Gets the provider's identity IDs from
# ExternalIdentity (lodge) first, then filters ExternalIdentitySession
# (authnd-prod) by those IDs. Both queries stay within their own cluster.
#
# This "provider-first" direction is efficient because the provider's
# identity set is bounded (one business's employees), while the session
# scope can be very large (e.g., ExternalIdentitySession.active covers
# all active sessions platform-wide).
#
# The `scope:` parameter carries pre-filtered context (e.g., user association,
# .active) — it is NOT intended to be further composed after construction.
class ExternalIdentitySession::SsoProviderLookup
  BATCH_SIZE = 500

  # @param provider [ExternalProvider, SamlProvider] the SSO provider to look up sessions for
  # @param scope [ActiveRecord::Relation] pre-filtered relation (user association, .active, etc.)
  def initialize(provider, scope: ExternalIdentitySession.all)
    @provider = provider
    @scope = scope
  end

  # Optimized existence check — stops at first batch that has a match.
  def exists?
    scope_identity_ids_each_batch do |batch_ids|
      return true if provider_identity_exists?(batch_ids)
    end
    false
  end

  # Find a specific session by ID within sessions for this provider.
  # Short-circuits on first find.
  def find_session(session_id)
    session = @scope.find_by(id: session_id)
    return nil unless session

    provider_identity_exists?([session.external_identity_id]) ? session : nil
  end

  # Returns all matching sessions as an Array (not a Relation).
  def sessions
    results = []
    scope_identity_ids_each_batch do |batch_ids|
      matching_ids = provider_identity_ids(batch_ids)
      next if matching_ids.empty?

      results.concat(@scope.where(external_identity_id: matching_ids).to_a)
    end
    results
  end

  # Destroy sessions in batches (fires callbacks — for revocation jobs).
  def destroy_all_in_batches(of: 1000)
    scope_identity_ids_each_batch do |batch_ids|
      matching_ids = provider_identity_ids(batch_ids)
      next if matching_ids.empty?

      @scope.where(external_identity_id: matching_ids).in_batches(of: of).destroy_all
    end
  end

  # Delete sessions in batches with throttling (no callbacks — for soft delete).
  def delete_all_in_batches(of: 1000)
    scope_identity_ids_each_batch do |batch_ids|
      matching_ids = provider_identity_ids(batch_ids)
      next if matching_ids.empty?

      @scope.where(external_identity_id: matching_ids).in_batches(of: of) do |batch|
        ExternalIdentitySession.throttle_writes_with_retry do
          batch.delete_all
        end
      end
    end
  end

  private

  # Get this provider's identity IDs first (lodge query, bounded by provider size),
  # then pluck from the scope filtered by those IDs (authnd-prod query, bounded).
  # This avoids a full table scan on external_identity_sessions when the scope is
  # broad (e.g., ExternalIdentitySession.active from SoftDeleteBusinessJob).
  def scope_identity_ids_each_batch(&block)
    if FeatureFlag.vexi.enabled?(:sso_provider_lookup_provider_first, default: false)
      provider_first_identity_ids_each_batch(&block)
    else
      scope_first_identity_ids_each_batch(&block)
    end
  end

  # Original scope-first direction: pluck all identity IDs from scope, then batch.
  # Efficient when scope is small (single user), but causes full table scans when
  # scope is broad (e.g., ExternalIdentitySession.active).
  def scope_first_identity_ids_each_batch(&block)
    identity_ids = @scope.pluck(:external_identity_id)
    identity_ids.each_slice(BATCH_SIZE, &block)
  end

  # Provider-first direction: get provider identity IDs first (lodge, bounded by
  # provider size), then filter scope by those IDs (authnd-prod, bounded).
  # Avoids full table scan when scope is broad.
  def provider_first_identity_ids_each_batch(&block)
    all_provider_ids = ExternalIdentity
      .where(provider_id: @provider.id, provider_type: @provider.class.name)
      .pluck(:id)

    return if all_provider_ids.empty?

    all_provider_ids.each_slice(BATCH_SIZE) do |provider_batch|
      scope_ids = @scope.where(external_identity_id: provider_batch).pluck(:external_identity_id)
      next if scope_ids.empty?
      yield scope_ids
    end
  end

  # Check if any of the given identity IDs belong to this provider.
  def provider_identity_exists?(identity_ids)
    ExternalIdentity
      .where(id: identity_ids, provider_id: @provider.id, provider_type: @provider.class.name)
      .exists?
  end

  # Return the subset of identity IDs that belong to this provider.
  def provider_identity_ids(identity_ids)
    ExternalIdentity
      .where(id: identity_ids, provider_id: @provider.id, provider_type: @provider.class.name)
      .pluck(:id)
  end
end
