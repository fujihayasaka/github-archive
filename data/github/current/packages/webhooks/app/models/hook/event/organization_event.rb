# typed: true
# frozen_string_literal: true

class Hook::Event::OrganizationEvent < Hook::Event
  supports_targets Organization, Business, Integration

  def self.description(desc = nil)
    actions = []

    # only available in enterprise
    if GitHub.extended_org_hooks_enabled?
      actions += [:created]
    end

    # In dotcom we always send organization deletion hooks.
    # In enterprise, sending the organization deletion hook is configurable
    if GitHub.dotcom_request? || GitHub.extended_org_hooks_enabled?
      actions += [:deleted]
    end

    actions += [
      :renamed,
      :member_invited,
      :member_added,
      :member_removed,
    ]

    actions.map! { |action|  action.to_s.humanize(capitalize: false) }

    @description = "Organization #{actions.to_sentence(last_word_connector: ", or ")}."
  end

  event_attr :action, :organization_id, required: true
  event_attr :user_id, :actor_id, :invitation_id, :changes

  def organization
    @organization ||= Organization.find_by(id: organization_id)
  end

  def user
    if user_id_required? && user_id.nil?
      raise MissingRequiredAttribute.new(self.class.name, :user_id)
    else
      @user ||= User.find_by(id: user_id)
    end
  end

  def invitation
    if invitation_id_required? && invitation_id.nil?
      raise MissingRequiredAttribute.new(self.class.name, :invitation_id)
    else
      @invitation ||= OrganizationInvitation.find_by(id: invitation_id)
    end
  end

  def actor
    @actor ||= (User.find_by(id: actor_id) || User.ghost)
  end

  def target_organization
    organization
  end

  def target_business
    if action.to_sym == :deleted
      # If the Organization is removed from its owning Business on deletion, find the Business
      # via SoftDeletedOrganization record.
      organization.business || SoftDeletedOrganization.find_by(organization: organization)&.business
    else
      super
    end
  end

  def deliverable?
    return false unless target_organization.present?
    case action.to_sym
    when :member_invited
      invitation.present?
    when :member_added, :member_removed
      user.present?
    else
      true
    end
  end

  def changes
    return unless changes_attr

    {}.tap do |hash|
      hash[:login] = { from: changes_attr[:old_login] } if login_changed?
    end
  end

  private

  def user_id_required?
    [:member_removed, :member_added].include? action.to_sym
  end

  def invitation_id_required?
    action.to_sym == :member_invited
  end

  def login_changed?
    action.to_sym == :renamed && changes_attr[:old_login].present?
  end

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end
end
