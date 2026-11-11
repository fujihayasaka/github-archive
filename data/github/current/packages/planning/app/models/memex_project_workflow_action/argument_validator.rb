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
      if record.workflow.trigger_type == "auto_assign_agent"
        validate_auto_assign_agent_field(record)
      elsif record.workflow.trigger_type == "project_item_column_update"
        validate_field(record)
      else
        validate_query(record)
      end
    when :get_items
      validate_query(record, allow_empty: true, validate_tokens: true)
      validate_repository_id(record)
    when :add_project_item
      validate_repository_id(record) unless record.arguments["subIssue"]
    when :assign_copilot
      validate_assign_copilot_arguments(record)
    end
  end

  def validate_assign_copilot_arguments(record)
    instruction = record.arguments["instruction"]
    destination = record.arguments["destinationFieldOptionId"]

    if instruction.present? && instruction.length > INSTRUCTION_MAX_LENGTH
      record.errors.add(:instruction, "must be #{INSTRUCTION_MAX_LENGTH} characters or fewer")
    end

    if destination.present?
      # Destination must not equal the source column option (prevents loops)
      source_action = record.workflow&.actions&.detect { |a| a.action_type == "get_project_items" }
      if source_action && source_action.arguments["fieldOptionId"].present? && source_action.arguments["fieldOptionId"].to_s == destination.to_s
        record.errors.add(:destination, "column must be different from the source column")
      end

      # Destination must be a valid option on the status column
      if source_action && source_action.arguments["fieldId"].present?
        field = record.workflow&.memex_project&.columns&.detect { |c| c.id == source_action.arguments["fieldId"].to_i }
        if field && field.single_select? && !field.single_select_option(destination)
          record.errors.add(:destination, "must be a valid status column option")
        end
      end
    end

    validate_allowed_repositories(record)
  end

  def validate_allowed_repositories(record)
    repos = record.arguments["allowedRepositories"]
    return unless repos.present?

    unless repos.is_a?(Array)
      record.errors.add(:allowed_repositories, "must be an array")
      return
    end

    # Currently limited to 1 repository; will increase when multi-repo infrastructure lands
    if repos.length > MAX_ALLOWED_REPOSITORIES
      record.errors.add(:allowed_repositories, "must have at most #{MAX_ALLOWED_REPOSITORIES} entries")
      return
    end

    repos.each do |nwo|
      unless nwo.is_a?(String) && nwo.match?(%r{\A[^/]+/[^/]+\z})
        record.errors.add(:allowed_repositories, "entries must be in 'owner/repo' format")
      end
    end
  end

  # Aligned with Copilot::CustomInstructions::CHAR_LIMIT and CopilotSpace::MAX_GENERAL_INSTRUCTIONS_LENGTH
  INSTRUCTION_MAX_LENGTH = 4_000
  # Will increase when multi-repo task infrastructure is available
  MAX_ALLOWED_REPOSITORIES = 1

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

  # Auto-assign agent's get_project_items runner requires both fieldId and fieldOptionId
  # to take the field-filter path; without the option it falls through to the
  # query path and crashes on a nil query at runtime. We allow saving a draft
  # configuration without an option, but block enabling it.
  def validate_auto_assign_agent_field(record)
    field = record.memex_project_column

    unless field
      record.errors.add(:field, "argument can't be blank")
      return
    end

    return unless record.workflow&.enabled?

    if record.arguments["fieldOptionId"].blank?
      record.errors.add(:field_option, "argument can't be blank when auto-assign agent workflow is enabled")
    end
  end
end
