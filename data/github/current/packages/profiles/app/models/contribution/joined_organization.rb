# typed: true
# frozen_string_literal: true

class Contribution::JoinedOrganization < Contribution
  # We didn't start storing organization membership in the abilities table till
  # January 2014. Ignore all Ability records created before Febuary 2014 so that
  # we won't mislabel a user as having joined an org in January 2014 when they
  # really joined earlier.
  CUTOFF_DATE = DateTime.new(2014, 2, 1).freeze

  def organization
    subject.first
  end

  def organization_id
    organization.id
  end

  def login
    organization.login
  end

  def associated_subject
    organization
  end

  def occurred_at
    subject.last.in_time_zone
  end

  def platform_type_name
    "JoinedOrganizationContribution"
  end

  def id
    organization_id
  end

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure(
      "joined_organization_subjects_for",
      tags: ["lightweight:#{lightweight}"],
    ) do
      scope = Ability
                     .where(subject_type: "Organization", actor_type: "User", actor_id: user,
                            created_at: date_range_to_time_range(date_range))
                     .where("created_at >= ?", CUTOFF_DATE)

      if organization_id
        scope = scope.where(subject_id: organization_id)
      end

      organization_created_map = scope.distinct.pluck(:subject_id, :created_at).to_h
      ids = organization_created_map.keys - excluded_organization_ids
      orgs = Organization.not_spammy.where(id: ids)

      orgs.map do |org|
        [org, organization_created_map[org.id]]
      end
    end
  end
end
