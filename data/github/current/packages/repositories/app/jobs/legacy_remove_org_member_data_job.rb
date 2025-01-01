# typed: false
# frozen_string_literal: true

# This is an abstract class that should not be used directly
# Inheret from this class. ex RemoveOrgMemberForks

class LegacyRemoveOrgMemberDataJob < ApplicationJob
  queue_as :remove_org_member_data

  attr_accessor :org, :user, :restorable

  def self.enqueue(organization, user)
    self.perform_later("organization_id" => organization.id, "user_id" => user.id)
  end

  around_perform do |job, block|
    options = job.arguments.first
    organization_id = options.fetch("organization_id")
    user_id = options.fetch("user_id")
    job.org = Organization.find_by_id(organization_id)
    job.user = User.find_by_id(user_id)

    # if there is no user_id or org_id there's not much we can do
    # so we silently fail
    next unless job.org.present? && job.user.present?

    job.restorable = Restorable::OrganizationUser.continue(org, user)

    block.call

    job.user.reload
  end

  def inaccessible_org_repos(batch, &block)
    batch.reject do |repo|
      repo_to_check = block&.call(repo) || repo
      repo_to_check.pullable_by_user_or_no_plan_owner?(user)
    end
  end

  def perform(options)
    raise NotImplementedError
  end
end
