# typed: true
# frozen_string_literal: true

class Hook::Event::InstallationTargetEvent < Hook::Event
  supports_targets Integration

  event_attr :changes, :target_id, :target_type, required: true
  event_attr :actor_id

  description "A GitHub App installation target is renamed."

  def deliverable?
    target.present? && (login_changed? || slug_changed?)
  end

  def action
    :renamed
  end

  def actor
    return @actor if defined?(@actor)
    @actor = User.find_by(id: actor_id)
  end

  def changes
    return unless changes_attr

    {}.tap do |hash|
      if slug_changed?
        hash[:slug] = { from: changes_attr[:slug_was] }
      else
        hash[:login] = { from: changes_attr[:old_login] }
      end
    end
  end

  def subscribed_hooks
    installations = IntegrationInstallation.not_suspended.with_target(target)
    return [] if installations.none?

    integration_ids = installations.pluck(:integration_id)
    Hook.subscribed_to_integrator_event(event_type, installation_target_ids: integration_ids).active
  end

  def target
    return @target if defined?(@target)

    @target = case target_type
    when "Business"
      Business.find_by(id: target_id)
    when "Organization", "User"
      User.find_by(id: target_id)
    end
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def login_changed?
    target.is_a?(User) && changes_attr[:old_login].present?
  end

  def slug_changed?
    target.is_a?(Business) && changes_attr[:slug_was].present?
  end
end
