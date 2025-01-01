# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class Helpers
    extend T::Sig

    # Blackbird prioritizes indexing code for paying customers and orgs that are part of a business (enterprise
    # account). Centralizing this logic so that the hydro events and the blackbird internal api can have a consistent
    # view.
    sig { params(repo: Repository).returns(T::Boolean) }
    def self.repository_owner_is_paying_customer?(repo)
      return true if GitHub.multi_tenant_enterprise?
      owner = repo.owner
      !!(owner.present? &&
        (owner.paying_customer? ||
          Business::OrganizationMembership.exists?(organization: repo.owner)))
    end
  end
end
