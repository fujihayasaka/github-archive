# typed: true
# frozen_string_literal: true

class Contribution::JoinedGitHub < Contribution

  def associated_subject
    user
  end

  def occurred_at
    user.created_at
  end

  # Public: Formats the contribution time like 'March 17, 2009'.
  def pretty_date
    occurred_at.strftime("%B %-d, %Y")
  end

  def id
    user.id
  end

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure("joined_github_subjects_for", tags: ["lightweight:#{lightweight}"]) do
      subject = first_subject_for(user)
      date_range.cover?(subject.created_at.to_date) ? [subject] : []
    end
  end

  def self.first_subject_for(user, excluded_organization_ids: [])
    user
  end

  def platform_type_name
    "JoinedGitHubContribution"
  end
end
