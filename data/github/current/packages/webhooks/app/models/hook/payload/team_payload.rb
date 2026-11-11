# typed: true
# frozen_string_literal: true

class Hook::Payload::TeamPayload < Hook::Payload
  ACTIONS_TO_INCLUDE_PERMISSIONS = [:edited, :added_to_repository, :removed_from_repository]

  def to_payload_hash
    action  = hook_event.action
    team    = hook_event.team
    repo    = hook_event.target_repository

    changes_payload.tap do |hash|
      hash[:action] = action
      hash[:team]   = api_serialize(:team_hash, team)

      if repo.present? && ACTIONS_TO_INCLUDE_PERMISSIONS.include?(action.to_sym)
        hash[:repository] = api_serialize(:team_repo_with_custom_properties_hash, repo, team: team)
      end
    end
  end
end
