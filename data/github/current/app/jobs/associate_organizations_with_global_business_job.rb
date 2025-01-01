# typed: true
# frozen_string_literal: true

class AssociateOrganizationsWithGlobalBusinessJob < ApplicationJob
  include GitHub::Memoizer

  extend T::Sig

  schedule interval: 1.day, condition: -> { GitHub.enterprise? }

  queue_as :associate_organizations_with_global_business

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform
    return unless GitHub.enterprise?

    unassociated_orgs.each do |org|
      with_write do
        GitHub.global_business.add_organization(org)
      end
    end
  end

  private

  memoize def unassociated_orgs
    Organization.excluding_github_enterprise_org.where.missing(:business_membership)
  end
end
