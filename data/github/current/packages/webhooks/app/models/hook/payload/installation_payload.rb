# typed: true
# frozen_string_literal: true

class Hook::Payload::InstallationPayload < Hook::Payload

  def to_payload_hash
    {}.tap do |opts|
      opts[:action]       = hook_event.action
      opts[:installation] = installation_hash

      case hook_event.action.to_s
      when "created"
        opts[:repositories] = repositories_array(hook_event.repositories)
        opts[:requester] = api_serialize(:simple_user_hash, hook_event.requester)
      when "deleted"
        opts[:repositories] = repositories_array(hook_event.repositories)
      end
    end
  end

  private

  def installation_hash
    api_serialize(:installation_hash, hook_event.installation)
  end

  def repositories_array(repositories)
    return [] if repositories.blank?

    GitHub.dogstats.gauge("installation.payload.repositories.count", repositories.size)

    if hook_event.integration.feature_flag_enabled_or_raise?(:webhooks_installation_payload_repositories_prefill) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      collection = []

      repositories.in_batches(of: 500) do |batch|
        GitHub::PrefillAssociations.prefill_associations(batch, :network)
        batch.each do |repo|
          collection << api_serialize(:repository_identifier_hash, repo)
        end
      end

      collection
    else
      repositories.inject([]) do |collection, repo|
        collection << api_serialize(:repository_identifier_hash, repo)
      end
    end
  end
end
