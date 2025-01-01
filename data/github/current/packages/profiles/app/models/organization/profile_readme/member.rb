# typed: true
# frozen_string_literal: true

class Organization::ProfileReadme::Member < Organization::ProfileReadme::Base
  def public?
    false
  end

  # The private configuration repository: .github-private
  def repository
    return @repository if defined?(@repository)
    @repository = organization.private_configuration_repository
  end

  private

  def type
    "member"
  end

  def fetch_readme
    return nil unless repository.present?

    # TODO: do we need it to be async?
    repository.async_network.then do
      repository.org_member_profile_readme
    end
  end
end
