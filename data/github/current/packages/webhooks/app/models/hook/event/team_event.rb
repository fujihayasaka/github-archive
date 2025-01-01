# typed: true
# frozen_string_literal: true

class Hook::Event::TeamEvent < Hook::Event
  supports_targets Organization, Business, Integration

  description "Team is created, deleted, edited, or added to/removed from a repository."

  event_attr :action, :team_id, required: true
  event_attr :actor_id, to_be_required: true
  event_attr :changes, :repo_id

  def actor
    # TODO: Once marked as required, change to:
    #@actor ||= User.find(actor_id)
    @actor ||= User.find_by(id: actor_id)
  end

  def team
    @team ||= Team.find_by(id: team_id)
  end

  def changes
    return unless changes_attr

    {}.tap do |hash|
      if name_changed?
        hash[:name] = { from: changes_attr[:old_name] }
      end

      if description_changed?
        hash[:description] = { from: changes_attr[:old_description] }
      end

      if privacy_changed?
        hash[:privacy] = { from: changes_attr[:old_privacy] }
      end

      if permissions_changed?
        hash[:repository] = {
          permissions: {
            from: {
              push: changes_attr[:old_permissions][:push],
              pull: changes_attr[:old_permissions][:pull],
              admin: changes_attr[:old_permissions][:admin],
            },
          },
        }
      end
    end
  end

  def target_organization
    team&.organization
  end

  def target_repository
    return unless repo_id.present?
    Repositories.domain.active_by_id(repo_id)
  end

  def deliverable?
    target_organization.present?
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def description_changed?
    changes_attr[:old_description]
  end

  def name_changed?
    changes_attr[:old_name]
  end

  def permissions_changed?
    changes_attr[:old_permissions]
  end

  def privacy_changed?
    changes_attr[:old_privacy]
  end
end
