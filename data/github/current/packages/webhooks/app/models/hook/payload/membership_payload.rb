# typed: true
# frozen_string_literal: true

class Hook::Payload::MembershipPayload < Hook::Payload

  def to_payload_hash
    Hash.new.tap do |payload|
      payload.update({
        action: hook_event.action,
        scope: hook_event.scope,
        member: member_hash,
        sender: sender_hash,
      })

      payload[:team] = team_hash if team_hash
    end
  end

  def member_hash
    @member_hash ||= if hook_event.member_deleted?
      {
        id: hook_event.member_id,
        login: hook_event.member_login,
        deleted: true,
      }
    else
      api_serialize(:user_hash, hook_event.member)
    end
  end

  def sender_hash
    @sender_hash ||= if hook_event.member_deleted_own_account?
      # If a user deletes their own account the actor will
      # be the same as the member and won't exist in DB anymore.
      {
        id: hook_event.member_id,
        login: hook_event.member_login,
        deleted: true,
      }
    else
      api_serialize(:user_hash, hook_event.actor)
    end
  end

  def team_hash
    @team_hash ||= if hook_event.team_deleted?
      {
        id: hook_event.team_id,
        name: hook_event.team_name,
        deleted: true,
      }
    elsif hook_event.team
      api_serialize(:team_hash, hook_event.team)
    end
  end

end
