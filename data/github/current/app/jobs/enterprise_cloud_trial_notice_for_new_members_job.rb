# typed: strict
# frozen_string_literal: true

class EnterpriseCloudTrialNoticeForNewMembersJob < ApplicationJob
  queue_as :set_enterprise_cloud_trial_notice

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(new_members: T::Array[User]).void }
  def perform(new_members)
    new_members.each do |member|
      with_write { GlobalNoticeNext.new(viewer: member).set_notice(:enterprise_cloud_trial) }
    end
  end
end
