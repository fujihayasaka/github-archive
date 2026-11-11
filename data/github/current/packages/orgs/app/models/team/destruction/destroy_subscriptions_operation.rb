# typed: true
# frozen_string_literal: true

module Team::Destruction

  # Unsubscribes all given users from the given teams, if they are not
  # a (direct or indirect) member.
  #
  class DestroySubscriptionsOperation

    # TODO type can be different for ancestor teams once we allow org teams to have enterprise team parents later.
    # We will need to revisit this once we support that scenario (this would likely need an additional sql query to fetch types).
    def initialize(member_ids, team_ids, type = "Team")
      @member_ids = member_ids
      @team_ids = team_ids
      @type = type
    end

    def execute
      start = Time.now
      @member_ids.each do |member_id|
        promises = @team_ids.map do |team_id|
          Platform::Loaders::IsTeamMemberCheck.load(member_id, team_id).then do |is_member|
            Notifications::Subject.new(type: @type, id: team_id) unless is_member
          end
        end

        teams_to_be_removed_from = Promise.all(promises).sync.compact
        unless teams_to_be_removed_from.empty?
          Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: member_id, lists: teams_to_be_removed_from)
        end
      end
      ms = (Time.now - start) * 1000
      GitHub.dogstats.distribution("team.destruction.destroy_subscriptions_operation.dist.duration", ms)
    end
  end
end
