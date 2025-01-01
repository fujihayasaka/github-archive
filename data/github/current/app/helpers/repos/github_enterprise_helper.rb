# typed: true
# frozen_string_literal: true

module Repos::GitHubEnterpriseHelper
  def restrict_create_repositories_in_personal_namespace?(user)
    business = if GitHub.single_business_environment?
      GitHub.global_business
    elsif user.is_enterprise_managed?
      user.enterprise_managed_business
    end

    business.present? ? business.restrict_create_repository_in_personal_namespace_enabled? : false
  end
end
