# typed: true
# frozen_string_literal: true

class Hook::Event::PersonalAccessTokenRequestEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Integration, Organization

  description "Personal access token request created, approved, denied, or cancelled."

  event_attr  :action,
              :actor_id,
              :user_programmatic_access_id,
              :target_id,
              :target_type,
              required: true

  event_attr  :token_expires_at,
              :repositories,
              :permissions_added,
              :permissions_upgraded,
              :permissions_unchanged

  # Currently, we only support PAT requests that target organizations.
  memoize def target_organization
    Organization.find(target_id) if target_type == "Organization"
  end

  # The actor that triggered this event.
  memoize def actor
    User.find(actor_id)
  end

  def requester_id
    personal_access_token_request.actor.id
  end

  # The user who created the PAT request.
  memoize def requester
    User.find(requester_id)
  end

  memoize def personal_access_token_request
    access = UserProgrammaticAccess.find(user_programmatic_access_id)
    case target_type
    when "Organization"
      ProgrammaticAccessGrantRequest.with_target_and_access(target_organization, access)
    else
      # Currently, we only support PAT requests that target organizations.
      nil
    end
  end

  def permissions_result
    {}.merge **permissions_unchanged, **permissions_added, **permissions_upgraded
  end

  def token_expired?
    return nil unless token_expires_at

    Time.now >= Time.parse(token_expires_at)
  end

  def deliverable?
    # We only want to deliver events for PAT requests that target organizations.
    return false if target_type != "Organization"

    # We want to ignore auto-approved tokens or tokens that do not require approval.
    return false if action == :created && personal_access_token_request.approvable_by?(requester)

    true
  end
end
