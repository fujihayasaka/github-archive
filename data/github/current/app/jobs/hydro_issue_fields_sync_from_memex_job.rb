# rubocop:todo GitHub/EnforcePackageAppStructure
# rubocop:disable Rails/ModuleNaming
# typed: true
# frozen_string_literal: true

require "github/config/issue_fields_projects_sync"

# This job is responsible for synchronizing issue fields from Memex to the Issues.
# This is a temporary job that will be removed once the issue fields are fully supported in Memex.
class HydroIssueFieldsSyncFromMemexJob < HydroMessageJob

  queue_as :hydro_issue_fields_sync_from_memex

  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    actor = message.dig(:actor)
    return unless actor.present?
    user = User.find_by(id: actor.dig(:id))
    return unless user.present?
    return unless FeatureFlag.vexi.enabled?(:issue_fields_sync_with_projects, user, default: false)

    project_item_id = message.dig(:project_item, :id)
    column_id = message.dig(:project_column, :id)
    column_name = message.dig(:project_column, :name)
    column_value = message.dig(:value)

    operation = if schema == "hydro.schemas.github.memex.v0.MemexProjectColumnValueCreate"
      "CREATE"
    elsif schema == "hydro.schemas.github.memex.v0.MemexProjectColumnValueUpdate"
      "UPDATE"
    elsif schema == "hydro.schemas.github.memex.v0.MemexProjectColumnValueDestroy"
      "DELETE"
    else
      "UNKNOWN"
    end

    result = perform_job(user, project_item_id, column_id, column_name, operation == "DELETE" ? nil : column_value)

    if FeatureFlag.vexi.enabled?(:issue_fields_sync_from_memex_logging, user, default: false)
      GitHub.logger.info(
        "info.message" => "Performed issue fields sync from Memex job",
        "gh.actor" => user.display_login,
        "gh.project_item_id" => project_item_id,
        "gh.project_id" => message.dig(:project, :id),
        "gh.project_column_id" => column_id,
        "gh.project_column_name" => column_name,
        "gh.column_value" => column_value,
        "gh.issue_id" => message.dig(:project_item, :issue, :global_relay_id),
        "gh.performed" => result.dig(:performed),
        "gh.reason" => result.dig(:reason),
        "gh.operation" => operation,
      )
    end
  end

  sig do
    params(user: User, project_item_id: T.untyped, column_id: T.untyped, column_name: T.untyped, column_value: T.untyped).returns(T::Hash[Symbol, T.untyped])
  end
  def perform_job(user, project_item_id, column_id, column_name, column_value)
    project_item = MemexProjectItem.find_by(id: project_item_id)
    return build_result(false, "Project item not found") unless project_item.present?

    project = project_item.memex_project
    return build_result(false, "Project not found") unless project.present?
    return build_result(false, "Project not enabled") unless GitHub::Config::IssueFieldsProjectsSync.enabled_for_project?(project.search_slug)

    issue_id = project_item.issue_id

    issue = Issue.where(id: issue_id).first
    return build_result(false, "Issue not found") unless issue.present?

    repository = issue.repository

    return build_result(false, "Repository not found") unless repository.present?
    return build_result(false, "Repository not enabled") unless GitHub::Config::IssueFieldsProjectsSync.enabled_for_repository?(repository)
    organization = repository.owner

    return build_result(false, "Organization not found") unless organization.present? && organization.is_a?(Organization)

    # get issue fields in the organization
    issue_fields = ::Issues.domain.issue_fields.by_organization(organization)

    # check if the there is an issue field that matches the project column name
    issue_field = issue_fields.find { |field| field.name == column_name }
    return build_result(false, "Issue field not found") unless issue_field

    is_issue_field_supported = issue_field.is_a?(IssueFieldSingleSelect) || issue_field.is_a?(IssueFieldDate) || issue_field.is_a?(IssueFieldText) || issue_field.is_a?(IssueFieldNumber)
    return build_result(false, "Invalid issue field type") unless is_issue_field_supported

    return build_result(false, "Issue field not enabled") unless GitHub::Config::IssueFieldsProjectsSync.enabled_for_field?(column_name)
    memex_project_column = MemexProjectColumn.find_by(id: column_id)

    return build_result(false, "Memex project column not found") unless memex_project_column

    with_write do
      issue_field_value = nil

      if memex_project_column.single_select? && issue_field.is_a?(IssueFieldSingleSelect)
        option = memex_project_column.single_select_option(column_value)

        current_issue_field_value = Issues.domain.issue_fields.get_issue_field_value(repository.id, issue_id, issue_field.id)
        current_issue_field_option = current_issue_field_value&.value
        current_column_option = option ? option["name"] : nil

        # if the option_id is the same as the current value, we do not need to update it
        memex_project_column_value = project_item.memex_project_column_values.find { |v| v.value == column_value }
        return build_result(false, "No change in value") if memex_project_column_value && current_issue_field_option == current_column_option

        if memex_project_column_value
          text_value = option["name"]
          # check if the issue field has an option with the same name
          existing_option = issue_field.options.find { |o| o.name == text_value }
          return build_result(false, "Existing option not found") unless existing_option
          issue_field_value = IssueFields::Builder.update_or_build_single_select_field_value(issue_field: issue_field, issue: issue, value: existing_option, actor: user)
        end
      elsif memex_project_column.date? && issue_field.is_a?(IssueFieldDate)
        if column_value && column_value.is_a?(String) && !column_value.empty?
          issue_field_value = IssueFields::Builder.update_or_build_date_field_value(issue_field: issue_field, issue: issue, value: column_value, actor: user)
        end
      elsif memex_project_column.text? && issue_field.is_a?(IssueFieldText)
        if column_value && column_value.is_a?(String) && !column_value.empty?
          issue_field_value = IssueFields::Builder.update_or_build_text_field_value(issue_field: issue_field, issue: issue, value: column_value, actor: user)
        end
      elsif memex_project_column.number? && issue_field.is_a?(IssueFieldNumber)
        if column_value && column_value.is_a?(String) && !column_value.empty?
          issue_field_value = IssueFields::Builder.update_or_build_number_field_value(issue_field: issue_field, issue: issue, value: column_value.to_i, actor: user)
        end
      else
        return build_result(false, "Memex project column and issue field have incompatible or unsupported types")
      end

      if issue_field_value
        issue_field_value.save!
      else
        ::Issues.domain.issue_fields.delete_field_value(issue_field: issue_field, issue: issue)
      end
    end

    build_result(true, nil)
  end

  sig do
    params(
      performed: T::Boolean,
      reason: T.nilable(String),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def build_result(performed, reason)
    {
      performed: performed,
      reason: reason
    }
  end
end


# rubocop:enable Rails/ModuleNaming
