# typed: true
# frozen_string_literal: true

module Stafftools
  class TeamView < Stafftools::User::IndexView

    attr_reader :team
    attr_reader :page

    def requests?
      requests.any?
    end

    def requests
      @requests ||= begin
        scope = team.pending_team_membership_requests
        scope.includes(requester: :profile).paginate \
          page: page,
          total_entries: scope.count
      end
    end

    def members?
      members.any?
    end

    def members
      @members ||= begin
        scope = team.members
        scope.order("login ASC").includes(:profile).paginate \
          page: page,
          total_entries: scope.count
      end
    end

    def all_members
      @all_members ||= begin
        team.members.order("login ASC").includes(:profile)
      end
    end

    def organization
      team.organization
    end

    def notification_status
      case team.notification_setting
      when "notifications_enabled"
        "Everyone will be notified when the team is @mentioned."
      when "notifications_disabled"
        "No one will receive notifications."
      end
    end
  end
end
