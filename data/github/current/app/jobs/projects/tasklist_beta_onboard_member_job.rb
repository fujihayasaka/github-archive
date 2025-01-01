# typed: true
# frozen_string_literal: true

module Projects
  class TasklistBetaOnboardMemberJob < ApplicationJob
    queue_as :projects_beta_signups
    retry_on_dirty_exit

    def perform(org_login)
      # get the org
      org = Organization.find_by_login(org_login)

      return if org.nil?

      # get membership from waitlist
      membership = EarlyAccessMembership.projects_tasklist_waitlist.find_by(member_id: org.id)

      return if membership.nil?

      # fetch all subscribers for original feature flag
      subscriber_ids = EarlyAccessSubscribers.get_subscriber_ids(HierarchyAndRoadmapBeta.new.feature_slug, membership.id)
      # if no subscribers found, use the actor from the EarlyAccessMembership
      if subscriber_ids.empty?
        subscriber_ids.push(membership.actor_id)
      end

      subscriber_ids.each do |subscriber_id|
        admin = org.admins.find_by(id: subscriber_id)
        # generate mailer and send to each subscriber if they are an admin
        if admin
          GlobalInstrumenter.instrument("user.beta_feature.enroll",
            actor: admin,
            action: "enroll",
            feature: "projects_tasklist",
          )
        end
      end
    end
  end
end
