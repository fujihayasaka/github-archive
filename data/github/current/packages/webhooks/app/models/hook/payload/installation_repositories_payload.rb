# typed: true
# frozen_string_literal: true

class Hook::Payload::InstallationRepositoriesPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      installation: installation_hash,
      repository_selection: hook_event.repository_selection,
      repositories_added: repositories_array(hook_event.repositories_added),
      repositories_removed: repositories_array(hook_event.repositories_removed),
      requester: api_serialize(:simple_user_hash, hook_event.requester)
    }
  end

  private

  def installation_hash
    api_serialize(:installation_hash, hook_event.installation)
  end

  def repositories_array(repository_ids)
    return [] if repository_ids.blank?

    scope = Repository
      .includes(:network)
      .where(id: repository_ids)
      .select(:id, :name, :owner_id, :owner_login, :public, :source_id, :created_at)

    repositories = []

    scope.find_in_batches do |batch_of_repositories|
      batch_of_repositories.map do |repository|
        repositories << api_serialize(:repository_identifier_hash, repository)
      end
    end

    repositories
  end
end
