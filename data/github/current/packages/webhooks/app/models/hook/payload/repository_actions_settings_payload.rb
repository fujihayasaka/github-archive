# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryActionsSettingsPayload < Hook::Payload
  delegate :action, to: :hook_event
  delegate :updated_at, to: :repository

  def to_payload_hash
    {
      action:,
      updated_at:,
      updated_settings:
    }
  end

  private

  def repository
    hook_event.target_repository
  end

  def updated_settings
    {}.tap do |settings|
      # String values that just need to be truthy
      settings[:access_policy] = hook_event.new_policy if hook_event.updated_access_policy
      settings[:allowed_types] = hook_event.new_policy if hook_event.updated_allowed_types

      # Boolean values that can be `false` and need explicit nil checks
      github_owned_allowed = normalize_flag_value(hook_event.updated_github_owned_allowed)
      settings[:github_owned_allowed] = github_owned_allowed unless github_owned_allowed.nil?

      sha_pinning_required = normalize_flag_value(hook_event.updated_sha_pinning_required)
      settings[:sha_pinning_required] = sha_pinning_required unless sha_pinning_required.nil?

      verified_allowed = normalize_flag_value(hook_event.updated_verified_allowed)
      settings[:verified_allowed] = verified_allowed unless verified_allowed.nil?

      if normalize_flag_value(hook_event.updated_patterns)
        settings[:patterns] = allowed_action_patterns
      end
    end
  end

  def normalize_flag_value(value)
    case value
    when String
      value != "0"
    else
      value
    end
  end

  def allowed_action_patterns
    repository.actions_allowlist.allowed_action_patterns.pluck(:value)
  end
end
