# typed: true
# frozen_string_literal: true

class Hook::Event::ProjectsV2StatusUpdateEvent < Hook::Event
  include GitHub::Memoizer
  supports_targets Organization, Integration
  display_name "projects v2 status updates"
  description "Project status updates created, updated, or deleted."

  event_attr :action, :memex_project_status_id, :org_id, :actor_id, required: true
  event_attr :changes

  memoize def project_status
    MemexProjectStatus.find_by(id: memex_project_status_id)
  end

  memoize def actor
    User.find_by(id: actor_id)
  end

  memoize def target_organization
    Organization.find_by(id: org_id)
  end

  def deliverable?
    [project_status, target_organization].all?(&:present?)
  end

  memoize def changes
    changes_attr = attributes[:changes]&.deep_symbolize_keys
    return unless changes_attr

    changes_attr.reduce({}) do |result, (attribute, changes_for_attribute)|
      if [:body, :start_date, :target_date].include?(attribute)
        result[attribute] = {
          from: changes_for_attribute.first,
          to: changes_for_attribute.second
        }
      elsif attribute == :status_id
        result[:status] = {
          from: MemexProjectStatus.status_id_to_enum_string(changes_for_attribute.first),
          to: MemexProjectStatus.status_id_to_enum_string(changes_for_attribute.second)
        }
      end
      result
    end
  end
end
