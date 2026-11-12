# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
module ChatopIgnoreConditions
  extend ActiveSupport::Concern

  included do
    chatop :ignore_conditions, /ignore_conditions\s+(?<nwo>.*)?/, <<~DESC do
      NAME
        ignore_conditions - List all ignore conditions for an NWO

      SYNOPSIS
        ignore_conditions NWO [--remove IGNORE_CONDITION_ID] [--tenant TENANT]

        --remove IGNORE_CONDITION_ID - Remove the ignore condition with the given ID
        --tenant TENANT - The tenant to use

      EXAMPLES
        List the ignore conditions for `foo/bar`

          ignore_conditions foo/bar

        Remove the ignore condition with ID 1234

          ignore_conditions foo/bar --remove 1234
    DESC

      nwo = jsonrpc_params[:nwo]
      tenant = jsonrpc_params[:tenant]

      repo = find_by_nwo!(nwo, tenant)

      if jsonrpc_params[:remove]
        ignore_condition_to_remove = IgnoreCondition.find(jsonrpc_params[:remove].to_i)

        if ignore_condition_to_remove.update_config.repo != repo
          raise ChatopsController::CommandError,
                "Ignore condition #{ignore_condition_to_remove.id} does not belong to #{nwo}"
        else
          ignore_condition_to_remove.destroy!
        end

        jsonrpc_success("Removed ignore condition #{ignore_condition_to_remove.id} for #{nwo}")
      else
        header = "Repository: #{nwo} - GitHub ID: #{repo.github_id}\n"

        lines = [header]

        repo.active_update_configs.select { |uc| uc.ignore_conditions.any? }.each do |config|
          dir_info = if config.directories
                       "directories: #{config.directories},"
                     else
                       "directory: #{config.directory},"
                     end

          lines += [
            "Update Config: #{config.id} \t\t " \
            "package manager: #{config.package_manager} \t\t " \
            "#{dir_info}",
          ]
          lines += [ignore_conditions_table(config)]
          lines += ["\n"]
        end

        jsonrpc_success(lines.join("\n"))
      end
    end
  end

  private

  def ignore_conditions_table(update_config)
    Terminal::Table.new do |t|
      t.headings = ["ignore_condition_id", "ignored dependency name", "version requirement", "update type", "source"]
      t.rows = update_config.ignore_conditions.map do |ignore_condition|
        [
          ignore_condition.id,
          ignore_condition.dependency_name,
          ignore_condition.version_requirement,
          ignore_condition.update_types,
          source(ignore_condition),
        ]
      end
      t.align_column(1, :right)
      t.style = { border_top: false, border_bottom: false }
    end.to_s
  end

  def source(ignore_condition)
    if ignore_condition.from_config_file?
      "config file"
    else
      "issue comment (#{ignore_condition.issue_comment_id})"
    end
  end
end
# rubocop:enable Metrics/BlockLength
