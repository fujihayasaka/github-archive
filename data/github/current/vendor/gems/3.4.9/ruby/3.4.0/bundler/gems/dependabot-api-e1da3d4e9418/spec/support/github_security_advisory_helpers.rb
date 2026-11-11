# frozen_string_literal: true

module GitHubSecurityAdvisoryHelpers
  def mock_github_security_advisory_fetch(dependency_name:, package_manager:, patched_versions: nil,
                                          affected_versions: nil)
    assigned_attributes = {
      dependency_name: dependency_name,
      package_manager: package_manager,
    }
    assigned_attributes[:patched_versions] = patched_versions if patched_versions
    assigned_attributes[:affected_versions] = affected_versions if affected_versions

    advisory = FactoryBot.build(:github_security_advisory, **assigned_attributes)
    allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([advisory])
  end
end
