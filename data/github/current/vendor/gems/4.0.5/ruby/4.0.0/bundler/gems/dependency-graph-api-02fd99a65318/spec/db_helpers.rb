module Helpers
  def reset_vulnerability_data
    VulnerableVersionRange::GitHubVulnerability.delete_all
    VulnerableVersionRange::GitHubVulnerableVersionRange.delete_all
  end

  def reset_column_information
    VulnerableVersionRange::GitHubVulnerableVersionRange.reset_column_information
  end
end
