# typed: true
# frozen_string_literal: true

class Hook::Payload::IssuesPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      issue: api_serialize(:issue_hash, hook_event.issue),
    }.merge(meta_payload)
  end

  def meta_payload
    case hook_event.action.to_sym
    when :labeled, :unlabeled
      label_payload
    when :assigned, :unassigned
      assignee_payload
    when :edited
      changes_payload
    when :milestoned, :demilestoned
      milestone_payload
    when :typed, :untyped
      type_payload
    when :field_added, :field_removed
      field_payload
    when :transferred
      transferred_payload
    when :opened
      opened_payload
    else
      {}
    end
  end

  def label_payload
    return {} unless hook_event.label

    {
      label: api_serialize(:label_hash, hook_event.label, repo: hook_event.label.repository),
    }
  end

  def assignee_payload
    return {} unless hook_event.assignee

    {
      assignee: api_serialize(:user_hash, hook_event.assignee),
    }
  end

  def milestone_payload
    return {} unless hook_event.milestone

    {
      milestone: api_serialize(:milestone_hash, hook_event.milestone),
    }
  end

  def type_payload
    return {} unless hook_event.type

    {
      type: api_serialize(:type_hash, hook_event.type),
    }
  end

  def field_payload
    return {} unless hook_event.issue_field

    payload = {
      issue_field: {
        id: hook_event.issue_field.id,
        name: hook_event.issue_field.name,
        field_type: hook_event.issue_field.data_type.to_s.downcase,
      },
    }

    # For field_removed, use the stored data from changes since the record is deleted
    if hook_event.removed_field_value_data
      removed_data = hook_event.removed_field_value_data
      field_value_hash = {
        id: removed_data[:id],
      }

      # Add value-specific data based on field type
      if removed_data[:data_type] == "single_select" && removed_data[:option]
        field_value_hash[:value_id] = removed_data[:option_id]
        field_value_hash[:option] = removed_data[:option]
      elsif removed_data[:data_type] == "multi_select" && removed_data[:options]
        field_value_hash[:value_ids] = removed_data[:option_ids]
        field_value_hash[:options] = removed_data[:options]
      else
        # For text, date, number, and other field types, use the value directly
        field_value_hash[:value] = removed_data[:value] if removed_data[:value]
      end

      payload[:issue_field_value] = field_value_hash
    elsif hook_event.issue_field_value
      field_value_hash = {
        id: hook_event.issue_field_value.id,
      }

      # Add value-specific data based on field type
      if hook_event.issue_field_value.is_a?(IssueFieldSingleSelectValue)
        # For single select, try to get the option
        # If the value is being removed, the option association might be broken,
        # but we can still get the value (which is the option_id)
        if hook_event.issue_field_value.option
          option = hook_event.issue_field_value.option
          field_value_hash[:value_id] = option.id
          field_value_hash[:option] = {
            id: option.id,
            name: option.name,
            color: option.color,
            description: option.description,
          }
        else
          # If option association is broken (e.g., during removal), try to get the raw value
          # The raw value for single_select is the option_id
          option_id = hook_event.issue_field_value.read_attribute(:value)
          if option_id
            field_value_hash[:value_id] = option_id
            # Try to find the option from the field definition
            option = hook_event.issue_field.options.find { |opt| opt.id == option_id }
            if option
              field_value_hash[:option] = {
                id: option.id,
                name: option.name,
                color: option.color,
                description: option.description,
              }
            end
          end
        end
      elsif hook_event.issue_field_value.is_a?(IssueFieldMultiSelectValue)
        # For multi select, get all selected options
        opts = hook_event.issue_field_value.options
        if opts.present?
          field_value_hash[:value_ids] = opts.map(&:id)
          field_value_hash[:options] = opts.map do |opt|
            {
              id: opt.id,
              name: opt.name,
              color: opt.color,
              description: opt.description,
            }
          end
        else
          # If options association is broken, try to get the raw value (array of option IDs)
          raw_ids = hook_event.issue_field_value.read_attribute(:value)
          if raw_ids.is_a?(Array) && raw_ids.any?
            field_value_hash[:value_ids] = raw_ids
            # Try to find the options from the field definition
            field_options = hook_event.issue_field.options.select { |opt| raw_ids.include?(opt.id) }
            if field_options.any?
              field_value_hash[:options] = field_options.map do |opt|
                {
                  id: opt.id,
                  name: opt.name,
                  color: opt.color,
                  description: opt.description,
                }
              end
            end
          end
        end
      else
        # For text, date, number, and other field types
        if hook_event.issue_field_value.is_a?(IssueFieldDateValue)
          field_value_hash[:value] = hook_event.issue_field_value.value&.iso8601
        else
          # Text, number, and other types use value directly
          field_value_hash[:value] = hook_event.issue_field_value.value
        end
      end

      payload[:issue_field_value] = field_value_hash
    end

    # Add changes for field_added when a previous value existed (update scenario)
    # This allows consumers to detect updates vs first-time additions
    if hook_event.action.to_sym == :field_added && hook_event.field_changes.present?
      payload[:changes] = hook_event.field_changes
    end

    payload
  end

  def transferred_payload
    return {} unless hook_event.source_issue_transfer

    {
      changes: {
        new_issue: api_serialize(:issue_hash, hook_event.source_issue_transfer.new_issue),
        new_repository: api_serialize(:repository_with_custom_properties_hash, hook_event.source_issue_transfer.new_repository),
      },
    }
  end

  def opened_payload
    # Add old issue and old repository to the payload if the issue was opened as result
    # of an issue transfer
    return {} unless hook_event.target_issue_transfer

    {
      changes: {
        old_issue: api_serialize(:issue_hash, hook_event.target_issue_transfer.old_issue),
        old_repository: api_serialize(:repository_with_custom_properties_hash, hook_event.target_issue_transfer.old_repository),
      },
    }
  end
end
