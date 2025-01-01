# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryEvent < Hook::Event
  supports_targets Business, *DEFAULT_TARGETS

  def self.description(desc = nil)
    actions = self.description_actions.map { |action|  action.to_s.humanize(capitalize: false) }
    @description = "Repository #{actions.to_sentence(last_word_connector: ", or ")}."
  end

  def self.description_actions
    actions = [
      :created,
      :deleted,
      :archived,
      :unarchived,
      :publicized,
      :privatized,
      :edited,
      :renamed,
      :transferred,
    ]

    if GitHub.anonymous_git_access_enabled?
      actions += [
        :anonymous_access_enabled,
        :anonymous_access_disabled,
      ]
    end

    actions
  end

  event_attr :action, :actor_id, :repository_id, required: true
  event_attr :changes

  def target_repository
    # this includes both active and deleted repositories
    @target_repository ||= Repositories::Public.get_active_or_deleted(repository_id)
  end

  def actor
    @actor ||= User.find_by(id: actor_id) || User.ghost
  end

  def deliverable?
    target_repository.present?
  end

  def changes
    return unless changes_attr

    {}.tap do |hash|
      hash[:owner] = serialized_owner if repository_transferred?
      hash[:repository] = { name: { from: changes_attr[:old_name] } } if name_changed?

      if is_edited_action?
        [:description, :homepage, :default_branch, :topics].each do |attr|
          if changes_attr.has_key?(attr)
            hash[attr] = { from: changes_attr[:"old_#{attr}"] }
          end
        end
      end
    end
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def repository_transferred?
    action.to_sym == :transferred && changes_attr[:old_user_id].present?
  end

  def name_changed?
    action.to_sym == :renamed && changes_attr[:old_name].present?
  end

  def is_edited_action?
    action.to_sym == :edited
  end

  def serialized_owner
    serialized_resource_hash = if changes_attr[:owner_was_org]
      resource = Organization.find_by(id: changes_attr[:old_user_id])
      { organization: Api::Serializer.serialize(:organization_hash, resource) }
    else
      resource = User.find_by(id: changes_attr[:old_user_id])
      { user: Api::Serializer.serialize(:user_hash, resource) }
    end

    { from: serialized_resource_hash }
  end
end
