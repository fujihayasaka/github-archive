# typed: true
# frozen_string_literal: true

# Contributions reported from a GitHub Enterprise installation.
class Contribution::EnterpriseContributionInfo < Contribution
  def contributions_count
    subject.count
  end

  # We only capture the aggregate date for enterprise contributions,
  # so this will be an approximation
  def occurred_at
    subject.contributed_on.in_time_zone
  end

  # Only the user themself should have non-restricted visibility
  def associated_subject
    subject
  end

  def enterprise_contribution
    subject
  end

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure(
      "enterprise_contribution_subjects_for",
      tags: ["lightweight:#{lightweight}", "using_contribution_fetchers:false"],
    ) do
      # When filtering by an organization, return no contributions (until we have a way to line these up)
      return EnterpriseContribution.none if organization_id

      ::EnterpriseContribution.where(user: user).for_date(date_range).to_a
    end
  end
end
