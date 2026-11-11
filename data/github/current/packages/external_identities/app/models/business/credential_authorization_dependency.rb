# typed: true
# frozen_string_literal: true

module Business::CredentialAuthorizationDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Kernel }
  requires_ancestor { Business }

  included do
    include GitHub::Memoizer
  end

  BATCH_SIZE = 100
  COUNT_LIMIT = 10_000

  # Public: Count of fine-grained personal access tokens authorized for this business
  # Capped at COUNT_LIMIT to avoid timeouts
  #
  # Returns an Integer
  sig { returns(Integer) }
  def fine_grained_pat_count
    @fine_grained_pat_count ||= begin
      token_ids = Set.new

      organization_ids.each_slice(BATCH_SIZE) do |batch|
        raise_if_credential_count_time_budget_is_over

        ids = OrganizationProgrammaticAccessGrant
          .where(organization_id: batch)
          .limit(COUNT_LIMIT + 1 - token_ids.size)
          .pluck(:user_programmatic_access_id)
        token_ids.merge(ids)
        break if token_ids.size >= COUNT_LIMIT
      end

      [token_ids.size, COUNT_LIMIT].min
    end
  end

  # Public: Whether the fine-grained PAT count has reached the limit
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def fine_grained_pat_count_capped?
    fine_grained_pat_count >= COUNT_LIMIT
  end

  # Public: Count of classic personal access tokens authorized for this business
  # Capped at COUNT_LIMIT to avoid timeouts
  #
  # Returns an Integer
  sig { returns(Integer) }
  def classic_pat_count
    [classic_pat_credential_ids.size, COUNT_LIMIT].min
  end

  # Public: Whether the classic PAT count has reached the limit
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def classic_pat_count_capped?
    classic_pat_count >= COUNT_LIMIT
  end

  # Public: Count of SSH keys authorized for this business
  # Capped at COUNT_LIMIT to avoid timeouts
  #
  # Returns an Integer
  sig { returns(Integer) }
  def ssh_key_count
    @ssh_key_count ||= begin
      credential_ids = Set.new

      organization_ids.each_slice(BATCH_SIZE) do |batch|
        raise_if_credential_count_time_budget_is_over

        ids = Organization::CredentialAuthorization
          .where(organization_id: batch)
          .active
          .where(credential_type: "PublicKey")
          .limit(COUNT_LIMIT + 1 - credential_ids.size)
          .pluck(:credential_id)
        credential_ids.merge(ids)
        break if credential_ids.size >= COUNT_LIMIT
      end

      [credential_ids.size, COUNT_LIMIT].min
    end
  end

  # Public: Whether the SSH key count has reached the limit
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def ssh_key_count_capped?
    ssh_key_count >= COUNT_LIMIT
  end

  # Public: Count of OAuth application access tokens authorized for this business
  # Capped at COUNT_LIMIT to avoid timeouts
  #
  # Returns an Integer
  sig { returns(Integer) }
  def oauth_application_access_token_count
    @oauth_application_access_token_count ||= begin
      result = (all_oauth_credential_ids - classic_pat_credential_ids).size
      [result, COUNT_LIMIT].min
    end
  end

  # Public: Whether the OAuth application access token count has reached the limit
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def oauth_application_access_token_count_capped?
    oauth_application_access_token_count >= COUNT_LIMIT
  end

  # Public: Returns credential authorizations for a given actor using split queries
  # to avoid cross-cluster JOINs between business_organization_memberships and
  # organization_credential_authorizations.
  #
  # This fetches the business's active organization IDs first, then queries
  # organization_credential_authorizations by those org IDs.
  #
  # actor - The User or polymorphic actor to filter by.
  #
  # Returns an ActiveRecord::Relation of Organization::CredentialAuthorization records.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def credential_authorizations_for_actor(actor)
    org_ids = organization_ids
    return Organization::CredentialAuthorization.none if org_ids.empty?

    Organization::CredentialAuthorization
      .where(actor: actor)
      .batched_scope(:organization_id, values: org_ids)
  end

  private

  sig { returns(T::Set[Integer]) }
  def all_oauth_credential_ids
    return @all_oauth_credential_ids if defined?(@all_oauth_credential_ids)

    @all_oauth_credential_ids = Set.new

    # Limit needs to account for classic PATs (which will be subtracted) plus COUNT_LIMIT OAuth app tokens
    all_oauth_limit = COUNT_LIMIT + classic_pat_credential_ids.size

    organization_ids.each_slice(BATCH_SIZE) do |batch|
      raise_if_credential_count_time_budget_is_over

      ids = Organization::CredentialAuthorization
        .where(organization_id: batch)
        .active
        .where(credential_type: "OauthAccess")
        .limit(all_oauth_limit + 1 - @all_oauth_credential_ids.size)
        .pluck(:credential_id)
      @all_oauth_credential_ids.merge(ids)
      break if @all_oauth_credential_ids.size >= all_oauth_limit
    end

    @all_oauth_credential_ids
  end

  sig { returns(T::Set[Integer]) }
  def classic_pat_credential_ids
    return @classic_pat_credential_ids if defined?(@classic_pat_credential_ids)

    @classic_pat_credential_ids = Set.new

    organization_ids.each_slice(BATCH_SIZE) do |batch|
      raise_if_credential_count_time_budget_is_over

      ids = Organization::CredentialAuthorization
        .where(organization_id: batch)
        .active
        .where(credential_type: "OauthAccess")
        .where(is_application: false)
        .limit(COUNT_LIMIT + 1 - @classic_pat_credential_ids.size)
        .pluck(:credential_id)
      @classic_pat_credential_ids.merge(ids)
      break if @classic_pat_credential_ids.size >= COUNT_LIMIT
    end

    @classic_pat_credential_ids
  end

  sig { void }
  def raise_if_credential_count_time_budget_is_over
    GitHub::RequestDurationManager.raise_if_time_budget_is_over(time_buffer_ms: GitHub::ResilienceMixin::GRACEFUL_DEGRADATION_BUFFER_MS)
  end
end
