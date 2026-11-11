# typed: strict
# frozen_string_literal: true

module Organization::CredentialAuthorizationDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer

  requires_ancestor { Kernel }
  requires_ancestor { Organization }

  COUNT_LIMIT = 10_000

  # Public: Get all fine-grained PAT grants for this organization.
  #
  # Returns an ActiveRecord::Relation of OrganizationProgrammaticAccessGrant
  sig { returns(ActiveRecord::Relation) }
  def org_fine_grained_pat_grants
    OrganizationProgrammaticAccessGrant.where(organization_id: id)
  end

  # Public: Get all active credential authorizations for this organization.
  #
  # Returns an ActiveRecord::Relation of Organization::CredentialAuthorization
  sig { returns(ActiveRecord::Relation) }
  def org_credential_authorizations
    ::Organization::CredentialAuthorization
      .by_organization(organization: self)
      .active
  end

  # Public: Count of fine-grained personal access tokens authorized for this organization. Limited to
  # COUNT_LIMIT + 1 to avoid timeouts.
  #
  # Returns an Integer
  sig { returns(Integer) }
  memoize def fine_grained_pat_count
    org_fine_grained_pat_grants.limit(COUNT_LIMIT + 1).count
  end

  # Public: Count of classic personal access tokens authorized for this organization. Uses the is_application=false
  # flag to distinguish PATs from OAuth app tokens. Limited to COUNT_LIMIT + 1 to avoid timeouts.
  #
  # Returns an Integer
  sig { returns(Integer) }
  memoize def classic_pat_count
    org_credential_authorizations
      .where(credential_type: "OauthAccess", is_application: false)
      .limit(COUNT_LIMIT + 1).count
  end

  # Public: Count of SSH keys authorized for this organization.
  # Limited to COUNT_LIMIT + 1 to avoid timeouts.
  #
  # Returns an Integer
  sig { returns(Integer) }
  memoize def ssh_key_count
    org_credential_authorizations
      .where(credential_type: "PublicKey")
      .limit(COUNT_LIMIT + 1).count
  end

  # Public: Count of GitHub App and OAuth app user access tokens authorized for this organization. Both GitHub App
  # user-to-server tokens and OAuth app tokens are stored as OauthAccess with is_application=true. Limited to
  # COUNT_LIMIT + 1 to avoid timeouts.
  #
  # Returns an Integer
  sig { returns(Integer) }
  memoize def oauth_token_count
    org_credential_authorizations
      .where(credential_type: "OauthAccess", is_application: true)
      .limit(COUNT_LIMIT + 1).count
  end

  # Public: Fetch all credential counts for this organization, with timeout handling. This is used for lazy-loaded
  # credential counts.
  #
  # Returns a Hash with credential type sub-hashes or { timed_out: true } on timeout
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def fetch_credential_counts
    {
      fine_grained_pats: build_count_entry(fine_grained_pat_count),
      classic_pats: build_count_entry(classic_pat_count),
      ssh_keys: build_count_entry(ssh_key_count),
      oauth_tokens: build_count_entry(oauth_token_count),
      timed_out: false,
    }
  rescue ActiveRecord::StatementTimeout, ActiveRecord::QueryCanceled
    {
      timed_out: true,
    }
  end

  private

  # Private: Build a count/capped sub-hash for a credential type.
  #
  # Returns a Hash
  sig { params(raw_count: Integer).returns({ count: Integer, capped: T::Boolean }) }
  def build_count_entry(raw_count)
    { count: [raw_count, COUNT_LIMIT].min, capped: raw_count > COUNT_LIMIT }
  end
end
