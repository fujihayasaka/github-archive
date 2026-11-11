# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/config/ignore_condition"
require "github_helpers"

class RecordNotDestroyed < StandardError; end

class FindOrRemoveIgnoreCondition
  def initialize(pull_request:, dep_name: nil, version_requirement_to_remove: nil)
    @pull_request = pull_request
    @dep_name = dep_name
    @version_requirement_to_remove = version_requirement_to_remove
  end

  def run
    find_and_remove_ignore_conditions
  end

  private

  attr_reader :pull_request, :dep_name, :version_requirement_to_remove

  def find_and_remove_ignore_conditions
    # Get all the ignore conditions associated with the pull request update config, ignoring those from the config file
    ignore_conditions_to_check = pull_request.update_config.ignore_conditions.where(from_config_file: false)

    ignore_conditions_to_delete = find_ignore_conditions_to_delete(ignore_conditions_to_check)

    # Checks if there are any conditions to delete and if so, delete them all.
    # If all the conditions are deleted successfully, it returns true; otherwise, it returns false.
    ignore_conditions_to_delete.present? && ignore_conditions_to_delete.all? { |ic| destroy_ignore_condition(ic) }
  end

  def find_ignore_conditions_to_delete(ignore_conditions_to_check)
    if version_requirement_to_remove.nil?
      # Remove all the ignore conditions of a specific dependency
      ignore_conditions_to_check.select { |ic| ic.dependency_name == dep_name }
    else
      # Remove a specific ignore condition of a specific dependency
      ignore_conditions_to_check.select do |ic|
        ic.dependency_name == dep_name && ic.version_requirement == version_requirement_to_remove.to_s
      end
    end
  end

  def destroy_ignore_condition(ignore_condition)
    ignore_condition.destroy!
    true # record was successfully destroyed
  rescue ActiveRecord::RecordNotDestroyed
    raise "Failed to destroy #{ignore_condition} ignore condition."
  end
end
