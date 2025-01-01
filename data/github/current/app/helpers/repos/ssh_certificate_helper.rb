# typed: true
# frozen_string_literal: true

module Repos::SshCertificateHelper
  def can_use_ssh_certificates?(user:, repository:)
    if repository.in_organization?
      repository.try(:usable_ssh_certificate_authorities)&.any?
    else
      # if it's a personal repo and we're in GHES
      # check that the corresponding business has enabled user owned repo access configuration for ssh certificates
      # and the corresponding business has any CAs
      if GitHub.single_business_environment?
        business = GitHub.global_business
        business&.ssh_certificate_user_owned_repo_access_enabled? && business&.try(:usable_ssh_certificate_authorities)&.any?
      # if it's a personal repo and the user is an EMU
      # check that the corresponding business has enabled user owned repo access configuration for ssh certificates
      # and the corresponding business has any CAs
      # double check that the user is the repo owner (they should be, otherwise they shouldn't be able to see this page since EMUs can only create private personal repos)
      elsif user.is_enterprise_managed? && user == repository.owner
        business = user.enterprise_managed_business
        business&.ssh_certificate_user_owned_repo_access_enabled? && business&.try(:usable_ssh_certificate_authorities)&.any?
      end
    end
  end
end
