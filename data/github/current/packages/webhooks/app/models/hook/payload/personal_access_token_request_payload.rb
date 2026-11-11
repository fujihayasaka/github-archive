# typed: true
# frozen_string_literal: true

class Hook::Payload::PersonalAccessTokenRequestPayload < Hook::Payload

  def to_payload_hash
    {}.tap do |h|
      h[:action]                        = hook_event.action
      h[:personal_access_token_request] = personal_access_token_request_hash
    end
  end

  private

  def personal_access_token_request_hash
    method = case hook_event.target_type
    when "Organization"
      :org_pat_grant_request_hash
    else
      raise "Unsupported target type: #{hook_event.target_type}"
    end

    api_serialize(method, hook_event.personal_access_token_request, {
      hook:                  true,
      permissions_added:     hook_event.permissions_added,
      permissions_upgraded:  hook_event.permissions_upgraded,
      permissions_result:    hook_event.permissions_result,
      repositories:          hook_event.repositories ? repositories_array(hook_event.repositories) : nil,
      expires_at:            hook_event.token_expires_at,
      expired:               hook_event.token_expired?
    })
  end

  def repositories_array(repository_ids)
    return [] if repository_ids.blank?

    Repository
      .includes(:network)
      .where(id: repository_ids)
      .select(:id, :name, :owner_id, :owner_login, :public, :source_id, :created_at)
      .map { |repo| api_serialize(:repository_identifier_hash, repo) }
  end
end
