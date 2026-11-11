# typed: true
# frozen_string_literal: true

class Hook::Event::ProjectsV2Event < Hook::Event
  include GitHub::Memoizer
  supports_targets Organization, Integration
  display_name "projects v2"
  description "Project created, updated, deleted, closed, or reopened."

  event_attr :action, :project_id, :org_id, :actor_id, required: true
  event_attr :changes

  memoize def project
    MemexProject.find_by(id: project_id)
  end

  memoize def actor
    User.find_by(id: actor_id)
  end

  memoize def feature_flag_actor
    Organization.new(id: org_id).tap(&:readonly!)
  end

  memoize def target_organization
    Organization.find_by(id: org_id)
  end

  def deliverable?
    [project, target_organization].all?(&:present?)
  end

  memoize def changes
    changes_attr = T.let(attributes[:changes], T.nilable(T::Hash[String, T::Array[T.nilable(T.any(String, T::Boolean))]]))
    return unless changes_attr

    changes_attr.reduce({}) do |result, (attribute, changes_for_attribute)|
      if [:title, :description, :short_description].include?(attribute.to_sym)
        result[attribute] = {
          from: changes_for_attribute.first,
          to: changes_for_attribute.second
        }
      elsif attribute.to_sym == :public
        result[attribute] = {
          from: !!changes_for_attribute.first,
          to: !!changes_for_attribute.second
        }
      end
      result
    end
  end
end
