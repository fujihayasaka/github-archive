# typed: false
# frozen_string_literal: true

module Api::App::TeamDiscussionHelpers
  private def team(param_name: :team_id, org_param_name: :org_id)
    @team ||= find_team!
  end

  private def current_org
    @current_org ||= team.organization
  end

  private def set_organization
    current_org
  end

  private def require_team_discussions_enabled
    unless current_org.team_discussions_allowed?
      deliver_error!(
        410,
        message: "Team discussions are disabled for this organization.",
        documentation_url: "/v3/teams/discussions")
    end
  end

  private def find_discussion!(org_param_name: :org_id, team_param_name: :team_id, discussion_param_name: :discussion_number)
    discussion = DiscussionPost
      .where(team_id: team(param_name: team_param_name, org_param_name: org_param_name).id, number: discussion_number(param_name: discussion_param_name))
      .first
    record_or_404(discussion)
  end

  private def find_discussion_comment!(org_param_name: :org_id, team_param_name: :team_id, discussion_param_name: :discussion_number)
    comment = DiscussionPostReply
      .where(discussion_post_id: find_discussion!(org_param_name: org_param_name, team_param_name: team_param_name, discussion_param_name: discussion_param_name).id, number: comment_number)
      .first
    record_or_404(comment)
  end

  private def discussion_number(param_name: :number)
    int_id_param!(key: param_name)
  end

  private def comment_number
    int_id_param!(key: :comment_number)
  end
end
