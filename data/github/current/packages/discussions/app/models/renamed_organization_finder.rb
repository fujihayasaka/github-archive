# typed: true
# frozen_string_literal: true

# Finds an organization that has been renamed by traversing RepositoryRedirects.
class RenamedOrganizationFinder
  include GitHub::Memoizer

  attr_reader :original_name

  sig { params(name: T.untyped).returns(T.untyped) }
  def self.for_original_name(name)
    new(original_name: name).renamed_org
  end

  sig { params(original_name: T.untyped).void }
  def initialize(original_name:)
    @original_name = original_name
  end

  sig { returns(T.untyped) }
  memoize def renamed_org
    redirected_repo_candidate&.owner
  end

  private

  # Find a representative sample repo that has been renamed.
  # We're assuming that if the org has been renamed, most of its repos will
  # have a RepositoryRedirect record.
  #
  # This query catches the newest RepositoryRedirect for a repo in the org where
  # the repo is non-null. Ideally we'd look and see if the repo's owner was different
  # than `org_name`, but that'd be a cross-cluster join. By picking the newest
  # RepositoryRedirect we're hoping to avoid grabbing a record from before the
  # org was renamed.
  def redirected_repo_candidate
    RepositoryRedirect.active_by_old_owner(standardized_login).first&.repository
  end

  # In multi-tenant environments the redirect will have the tenant shortcode
  # suffixed to the login automatically on creation. We need to do the same
  # when we query for the redirect.
  def standardized_login
    return original_name unless User.scope_to_current_tenant?
    User.standardize_login(original_name, suffix: GitHub::CurrentTenant.get.shortcode)
  end
end
