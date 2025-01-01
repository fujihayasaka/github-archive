# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveBusinessMemberJob < ApplicationJob
  attr_reader :business, :actor, :member
  queue_as :remove_business_member
  retry_on_dirty_exit

  # Discard if Business::InvalidRemovalError is raised. This can happen if there are concurrent
  # attempts to remove the same user and the user is already removed when one attempt is processed.
  discard_on Business::InvalidRemovalError

  resolve_tenant_context do |business_id|
    Business.find_by(id: business_id)
  end

  retry_on(Organization::NoAdminsError, wait: 10.seconds, attempts: 2) do |job, exception|
    # Get list of organization where member is the last admin, as list of
    # strings ["org1", "org2", "org3"]
    org_list = exception.message.match(
      /User #{job.member.display_login} is the last admin in these organizations: (.*)/
    )[1].split(", ")
    BusinessMailer.remove_user_from_business_failed(
      job.business, job.actor, job.member, exception.class, org_list
    ).deliver_later
  end

  # Handle race condition if ET removal takes some time
  retry_on(Organization::UnableToRemoveEnterpriseTeamMemberError, wait: 10.seconds, attempts: 2)

  # Handle race condition if BT removal takes some time
  retry_on(Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError, wait: 10.seconds, attempts: 2)

  def perform(business_id, actor_id, member_id, options = {})
    return unless @business = Business.find_by(id: business_id)
    return unless @actor = User.find_by(id: actor_id)
    return unless @member = User.find_by(id: member_id)

    begin
      Business::MemberDestroyer.new(@business, @actor).destroy(@member)
    rescue Organization::NoAdminsError, Business::NoAdminsError => exception
      GitHub.logger.error({
        exception: exception,
        "code.namespace": self.class.name,
        "gh.business.id": business_id,
        "enduser.id": actor_id,
        "gh.thisuser": member_id,
      })
      Failbot.report(exception, job: RemoveBusinessMemberJob.name)

      GitHub.dogstats.increment \
        "remove_business_member_failed.race_condition",
        tags: [
          "error:#{exception.class}",
          "job:RemoveBusinessMemberJob",
          "business_id:#{@business.id}",
          "actor:#{@actor}",
          "member:#{@member}"
        ]

      if exception.is_a?(Business::NoAdminsError)
        # Send email here, with organizations empty
        BusinessMailer.remove_user_from_business_failed(
          @business, @actor, @member, exception.class
        ).deliver_later
      else
        # if the job has failed because the member is the last admin of an org
        # and they're trying to remove themselves from the business,
        # don't raise the exception since there's no point in retrying
        if @actor != @member
          raise exception
        end
      end
    end
  end
end
