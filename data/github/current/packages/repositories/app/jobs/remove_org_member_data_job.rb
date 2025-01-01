# typed: true
# frozen_string_literal: true

# This is an abstract class that should not be used directly
# Inheret from this class. ex RemoveOrgMemberForks

class RemoveOrgMemberDataJob < ApplicationJob
  queue_as :remove_org_member_data

  retry_on_dirty_exit

  # Discard the job if the org or user are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  attr_accessor :org, :user, :restorable

  before_perform do |job|
    job.org = job.arguments.first
    job.user = job.arguments.second
    job.restorable = Restorable::OrganizationUser.continue(org, user)
  end

  def inaccessible_org_repos(batch, &block)
    batch.reject do |repo|
      repo_to_check = block&.call(repo) || repo
      repo_to_check.pullable_by_user_or_no_plan_owner?(user)
    end
  end

  def perform(org, user)
    raise NotImplementedError
  end
end
