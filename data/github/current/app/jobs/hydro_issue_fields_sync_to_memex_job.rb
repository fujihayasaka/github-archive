# rubocop:todo GitHub/EnforcePackageAppStructure
# rubocop:disable Rails/ModuleNaming
# typed: true
# frozen_string_literal: true

require "github/config/issue_fields_projects_sync"

# This job is responsible for synchronizing issue fields to Memex.
# This is a temporary job that will be removed once the issue fields are fully supported in Memex.
class HydroIssueFieldsSyncToMemexJob < HydroMessageJob

  queue_as :hydro_issue_fields_sync_to_memex

  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    user = User.find_by(id: message.dig(:actor_id))
    return unless user.present?
    return unless FeatureFlag.vexi.enabled?(:issue_fields_sync_with_projects, user, default: false)

    result = perform_job(message)
    if FeatureFlag.vexi.enabled?(:issue_fields_sync_to_memex_logging, user, default: false)
      GitHub.logger.info(
        "info.message" => "Performed issue fields sync to Memex job",
        "gh.actor" => user.display_login,
        "gh.issue_id" => message.dig(:issue_id),
        "gh.issue_field_value_id" => message.dig(:issue_field_value_id),
        "gh.issue_field_id" => message.dig(:issue_field, :id),
        "gh.repository_id" => message.dig(:repository_id),
        "gh.performed" => result.dig(:performed),
        "gh.reason" => result.dig(:reason),
        "gh.project_items_synced" => result.dig(:project_items_synced),
        "gh.operation" => message[:operation] || "UNKNOWN",
      )
    end
  end

  private

  sig do
    params(message: T.untyped).returns(T::Hash[Symbol, T.untyped])
  end
  def perform_job(message)
    user = User.where(id: message.dig(:actor_id)).first
    issue_id = message.dig(:issue_id)
    issue = Issue.where(id: issue_id).first

    return build_result(false, "Issue not found", nil) unless issue.present?

    repository_id = message.dig(:repository_id)
    repository = Repository.where(id: repository_id).first

    return build_result(false, "Repository not found", nil) unless repository.present?
    return build_result(false, "Repository not enabled", nil) unless GitHub::Config::IssueFieldsProjectsSync.enabled_for_repository?(repository)

    issue_field_value_id = message.dig(:issue_field_value_id)
    issue_field_value = IssueFieldValue.where(id: issue_field_value_id).first
    return build_result(false, "Issue field value not found", nil) unless issue_field_value.present? || message[:operation] == :DELETE

    issue_field_id = message.dig(:issue_field, :id)
    issue_field = IssueField.where(id: issue_field_id).first
    return build_result(false, "Issue field not found", nil) unless issue_field.present?
    return build_result(false, "Issue field not enabled: #{issue_field.name}", nil) unless GitHub::Config::IssueFieldsProjectsSync.enabled_for_field?(issue_field.name)

    # if the issue field is not a single select, we do not need to sync it
    is_issue_field_supported = issue_field.is_a?(IssueFieldSingleSelect) || issue_field.is_a?(IssueFieldDate) || issue_field.is_a?(IssueFieldText) || issue_field.is_a?(IssueFieldNumber)
    return build_result(false, "Invalid issue field data type", nil) unless is_issue_field_supported

    issue_field_option = IssueFieldOption.where(id: message[:issue_field_option_id]).first

    project_items_synced = []
    performed = T.let(false, T::Boolean)
    issue.memex_projects.each do |memex_project|
      project_item_synced_failed_result = {
        project_id: memex_project.id,
        synced: false,
      }

      memex_project_column = memex_project.memex_project_columns.find_by(name: issue_field.name)

      if memex_project_column.nil?
        project_items_synced << project_item_synced_failed_result.merge(reason: "Matching column not found")
        next
      end

      # find the project item for the issue
      project_item = memex_project.memex_project_items.find_by(issue_id: issue.id)
      if project_item.nil?
        project_items_synced << project_item_synced_failed_result.merge(reason: "Project item not found")
        next
      end

      project = project_item.memex_project
      next unless project.present?
      if !GitHub::Config::IssueFieldsProjectsSync.enabled_for_project?(project.search_slug)
        project_items_synced << project_item_synced_failed_result.merge(reason: "Project not enabled")
        next
      end

      # find the column value for the project item
      memex_project_column_value = project_item.memex_project_column_values.find_by(memex_project_column_id: memex_project_column.id)

      new_memex_column_value = if memex_project_column.single_select? && issue_field.is_a?(IssueFieldSingleSelect)
        issue_field_option_value = if message[:operation] == :DELETE
          issue_field_option&.name
        else
          T.must(issue_field_value).value
        end

        option_ids = memex_project_column.settings_option_ids([issue_field_option_value])
        if !(option_ids.present? && option_ids.size == 1)
          project_items_synced << project_item_synced_failed_result.merge(reason: "Invalid options")
          next
        end

        option_id = option_ids.first

        # if the option_id is the same as the current value, we do not need to update it
        if memex_project_column_value && option_id == memex_project_column_value.value && message[:operation] != :DELETE
          project_items_synced << project_item_synced_failed_result.merge(reason: "No change in value")
          next
        end

        option_id
      elsif memex_project_column.date? && issue_field.is_a?(IssueFieldDate)
        issue_field_value ? issue_field_value.value.to_s : nil
      elsif memex_project_column.text? && issue_field.is_a?(IssueFieldText)
        issue_field_value ? issue_field_value.value : nil
      elsif memex_project_column.number? && issue_field.is_a?(IssueFieldNumber)
        issue_field_value ? issue_field_value.value : nil
      else
        project_items_synced << project_item_synced_failed_result.merge(reason: "Invalid column type")
        next
      end

      with_write do
        if memex_project_column_value
          # update the column value if it exists
          if message[:operation] != :DELETE
            memex_project_column_value.update(value: new_memex_column_value)
          else
            # if the new value is not present, delete the column value
            memex_project_column_value.destroy
          end
        else
          # create a new column value if it does not exist
          if issue_field_value_id.present?
            project_item.memex_project_column_values.create!(memex_project_column: memex_project_column, value: new_memex_column_value, creator: user)
          end
        end
        performed = true
        project_items_synced << {
          project_id: memex_project.id,
          synced: true
        }
      end
    end

    build_result(performed, nil, project_items_synced)
  end

  sig do
    params(
      performed: T::Boolean,
      reason: T.nilable(String),
      project_items_synced: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def build_result(performed, reason, project_items_synced)
    {
      performed: performed,
      reason: reason,
      project_items_synced: project_items_synced || [],
    }
  end
end

# rubocop:enable Rails/ModuleNaming, Rails/ModuleNaming
