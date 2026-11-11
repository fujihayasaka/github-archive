# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowAction::ArgumentValidator < ActiveModel::Validator
  def validate(record)
    unless record.arguments&.is_a?(Hash)
      record.errors.add(:arguments, "must be a Hash")
      return
    end

    case record.action_type&.to_sym
    when :set_field
      validate_set_field_arguments(record)
    when :get_project_items
      if record.workflow.trigger_type == "project_item_column_update"
        validate_field(record)
      else
        validate_query(record)
      end
    when :get_items
      validate_query(record, allow_empty: true, validate_tokens: true)
      validate_repository_id(record)
    when :add_project_item
      validate_repository_id(record) unless record.arguments["subIssue"]
    end
  end

  def validate_set_field_arguments(record)
    unless record.arguments["fieldId"].present?
      record.errors.add(:arguments, "must include a 'fieldId' value")
    end

    field = record.memex_project_column
    unless field
      record.errors.add(:field, "argument can't be blank")
      return
    end

    unless field.single_select?
      record.errors.add(:field, "argument must be of type single-select")
      return
    end

    # If there is a non-nil value present in `fieldOptionId`, it must match an
    # existing option.
    unless record.arguments["fieldOptionId"].nil? || field.single_select_option(record.arguments["fieldOptionId"])
      record.errors.add(:field_option, "argument must match an existing option")
      nil
    end
  end

  def validate_query(record, allow_empty: false, validate_tokens: false)
    query = record.arguments["query"]

    if !allow_empty && query.blank?
      record.errors.add(:query, "argument can't be blank")
    end

    if validate_tokens && !query.blank?
      tokens = Search::Memex::QueryParser.parse(query, normalizer: ->(q) { q.downcase.strip })
      validity = MemexProjectWorkflowAction::ItemsFilter.validate_tokens(tokens)
      unless validity[:valid]
        info = validity[:invalid_tokens].map { |t| "#{t[:keyword]}:#{t[:values].join(",")}" }.join(" ")
        record.errors.add(:query, "argument contains invalid tokens: #{info}")
      end
    end

    nil
  end

  def validate_repository_id(record)
    repository_id = record.arguments["repositoryId"]

    unless repository_id.present?
      record.errors.add(:repository_id, "argument can't be blank")
      nil
    end
  end

  def validate_field(record)
    field = record.memex_project_column

    unless field
      record.errors.add(:field, "argument can't be blank")
      nil
    end
  end
end
