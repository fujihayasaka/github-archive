# typed: true
# frozen_string_literal: true

class Hook::Event::ProjectsV2ItemEvent < Hook::Event
  include GitHub::Memoizer
  supports_targets Organization, Integration
  display_name "project v2 items"
  description "Project item created, edited, deleted, archived, restored, converted, or reordered."

  event_attr :action, :memex_project_item_id, :organization_id, :actor_id, required: true
  event_attr :changes, :changed_field_id

  memoize def item
    MemexProjectItem.find_by(id: memex_project_item_id)
  end

  memoize def column
    MemexProjectColumn.find_by(id: changed_field_id)
  end

  memoize def project
    item&.memex_project
  end

  memoize def actor
    User.find_by(id: actor_id)
  end

  memoize def feature_flag_actor
    # Rather than querying the database to load an organization just for a foreground
    # feature flag check, instead instantiate an unpersisted Organization to pass to
    # the feature flag middleware. This is equally valid, but more efficient.
    Organization.new(id: organization_id).tap(&:readonly!)
  end

  memoize def target_organization
    Organization.find_by(id: organization_id)
  end

  def single_select_option(option_id)
    option = column.settings.dig("options")&.find { |o| o["id"] == option_id }
    option&.slice("id", "name", "color", "description")
  end

  def iteration_setting(setting_id)
    setting = column.settings_all_iterations&.find { |o| o["id"] == setting_id }
    setting&.slice("id", "title", "duration", "start_date")
  end

  sig { returns(T.nilable(T::Array[T.any(String, Integer, Hash)])) }
  def changed_values
    values = attributes.dig(:changes, "value") || []

    if values.size != 2
      return nil
    end

    # Currently changed values are only supported for edited events, specifically generic types.
    # This includes text, number, date, single select and iteration fields.
    case column.data_type
    when "text", "number", "date"
      values
    when "single_select"
      values.map { |value| single_select_option(value) }
    when "iteration"
      values.map { |value| iteration_setting(value) }
    else
      nil
    end
  end

  sig { returns(T::Boolean) }
  def deliverable?
    [item, item&.content, project, target_organization].all?(&:present?) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T::Boolean) }
  def edited?
    action.to_sym == :edited
  end

  memoize def changes
    if edited? && column&.present?
      field_value = {
        field_node_id: column.global_relay_id,
        field_type: column.data_type,
        field_name: column.name,
        project_number: project.number
      }

      if changed_values&.present?
        field_value.merge!(from: changed_values&.dig(0), to: changed_values&.dig(1))
      end

      {
        field_value: field_value
      }
    elsif attributes[:changes].present?
      attributes[:changes]
    elsif edited?
      GitHub.logger.info(
        "No changes found in projects_v2_item :edit event",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.memex.item.id": item&.id,
        "gh.memex.column.id": column&.id || "",
      )
    end
  end
end
