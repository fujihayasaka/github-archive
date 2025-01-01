# typed: true
# frozen_string_literal: true

class Business::MemberDestroyer
  attr_reader :business, :actor

  def initialize(business, actor)
    @business = business
    @actor = actor
  end

  def destroy(member)
    ActiveRecord::Base.connected_to(role: :writing) { EnterpriseTeam.destroy_memberships_for(user_ids: [member.id], business_id: @business.id) }

    # One of our invariants for Organizations is that they should always have an owner.
    # Ownerless orgs are an exceptional state and indicate a bug of some sort.
    #
    # Here, we ensure that if the business member to be removed is also the last owner
    # for a business-associated organization, that the business owner initiating the
    # removal becomes an additional owner of that organization so that the removal of
    # the business member from the org will complete successfully as they are no longer
    # the last owner.
    #
    # Note: The preferred language is "organization owner," not "organization admin"
    # even though the predicate method is `last_admin?`.
    @business.organizations.each do |org|
      if org.last_admin?(member)
        ActiveRecord::Base.connected_to(role: :writing) { org.add_admin(@actor) }
      end
    end

    @business.remove_member \
      member,
      actor: @actor,
      reason: "#{@actor.login} is removing #{member.login} via the web interface."
  end
end
