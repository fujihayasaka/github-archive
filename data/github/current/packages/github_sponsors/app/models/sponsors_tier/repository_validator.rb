# typed: true
# frozen_string_literal: true

# Public: Checks if a Repository can be used for the Sponsors Only Repo feature
class SponsorsTier::RepositoryValidator
  # repository - The Repository to be validated.
  # sponsorable - The Sponsorable who is associated with the repository.
  def initialize(sponsorable:, repository:)
    @sponsorable = sponsorable
    @repository = repository
    @errors = []
  end

  def errors
    @_errors ||= begin
      validate_repository
      @errors
    end
  end

  private

  attr_reader :sponsorable, :repository

  def validate_repository
    validate_repo_is_private
    validate_repo_is_owner_or_adminable_by_sponsorable
    validate_repo_is_org_owned
    validate_repo_is_not_enterprise_managed
  end

  def validate_repo_is_private
    @errors << "must be private" unless repository.private?
  end

  def validate_repo_is_owner_or_adminable_by_sponsorable
    if sponsorable.organization?
      @errors << "owner must be #{sponsorable}" unless repository.owner == sponsorable
    elsif !repository.adminable_by?(sponsorable)
      @errors << "#{sponsorable} must be an admin of the selected repository"
    end
  end

  def validate_repo_is_org_owned
    @errors << "must be owned by an organization" unless Repositories::Public.organization_owned?(repository)
  end

  def validate_repo_is_not_enterprise_managed
    @errors << "must not be enterprise-managed" if repository.is_enterprise_managed?
  end
end
