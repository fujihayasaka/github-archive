# typed: true
# frozen_string_literal: true

class TransferOrganizationsBusinessOrchestration < BusinessOrchestration
  job_start

  step :ensure_sufficient_licenses_for_organizations do
    organizations.each do |organization|
      target_business.ensure_sufficient_licenses_for_organization!(organization)
    end
  end

  step :remove_organizations_from_source_business do
    organizations.each do |organization|
      T.must(business).remove_organization(organization, is_transfer: true, actor: actor)
    end
  end

  step :copy_personal_access_token_expiration_limits do
    organizations.each do |organization|
      organization.copy_personal_access_token_expiration_limits(T.must(business), actor: actor)
    end
  end

  step :update_internal_repositories do
    organizations.each do |organization|
      repo_ids = organization.repositories.pluck(:id)
      InternalRepository.where(repository_id: repo_ids).update_all(business_id: target_business.id)
    end
  end

  step :add_organizations_to_target_business do
    organizations.each do |organization|
      target_business.add_organization(organization, ensure_sufficient_licenses: false)
    end
  end

  private

  memoize def target_business
    Business.find_by(id: data[:target_business_id])
  end
end
