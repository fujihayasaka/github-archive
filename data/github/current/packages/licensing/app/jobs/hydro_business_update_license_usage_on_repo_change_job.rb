# typed: true
# frozen_string_literal: true

class HydroBusinessUpdateLicenseUsageOnRepoChangeJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig

  queue_as :hydro_business_update_license_usage_on_repo_change

  # retry_on ExpectedError
  # discard_on IgnoredError

  # Public: If the repository belongs to an org attached to a business,
  # schedule a license update job.

  # Returns nothing
  sig { void }
  def perform
    repository.owner&.business&.update_license_usage
  end
end
