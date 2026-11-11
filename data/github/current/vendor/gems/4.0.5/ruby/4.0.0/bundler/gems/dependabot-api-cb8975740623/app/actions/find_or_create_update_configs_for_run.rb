# frozen_string_literal: true

# Finds or creates UpdateConfigs for a requested run.
# Returns user-defined UpdateConfigs when present, reuses existing ephemeral
# ones when possible, otherwise creates new ephemeral ones.
#
# `target_branch` defaults to nil for vuln alerts (default branch only).
# Graph callers pass the event's ref_name so each branch gets its own config.
class FindOrCreateUpdateConfigsForRun
  attr_reader :repo, :package_manager, :directories, :user, :target_branch

  def initialize(repo:, package_manager:, directories:, user:, target_branch: nil)
    @repo = repo
    @package_manager = package_manager
    @directories = directories
    @user = user
    @target_branch = target_branch
  end

  # rubocop:disable Metrics/MethodLength
  def run
    unconfigured_directories = []
    update_configs_and_directories = {}

    ActiveRecord::Base.connected_to(role: :reading) do
      resolver = UpdateConfigResolver.for(repo).with_package_manager(package_manager).with_target_branch(target_branch)

      # Find configured UpdateConfigs for each directory, keep track of unconfigured directories

      directories.each do |directory|
        update_config = resolver.user_defined.with_directory(directory).first
        if update_config
          update_configs_and_directories[update_config] ||= []
          update_configs_and_directories[update_config] << directory
        else
          unconfigured_directories << directory
        end
      end

      # The user has configs that cover all the directories, nothing more to do.
      return update_configs_and_directories if unconfigured_directories.empty?

      # Rather than deleting UpdateConfigs to create one with perfect directory coverage,
      # we can reuse an existing UpdateConfig and override the directories in-memory. This
      # prevents unnecessary churn and avoids race conditions.
      # The caller needs to use the directories returned, not the ones on the UpdateConfig.
      ephemeral_update_config = resolver.ephemeral.first
      if ephemeral_update_config
        update_configs_and_directories[ephemeral_update_config] = unconfigured_directories.compact.sort
        return update_configs_and_directories
      end
    end

    new_update_config = create_new_ephemeral_update_config(unconfigured_directories)

    update_configs_and_directories[new_update_config] = unconfigured_directories
    update_configs_and_directories
  end
  # rubocop:enable Metrics/MethodLength

  private

  def create_new_ephemeral_update_config(directories)
    FindOrCreateUpdateConfig.new(
      repo: repo,
      update_config_details: {
        "package-manager" => package_manager,
        "update-schedule" => "never",
        "target-branch" => target_branch,
        "lockfile-only" => false,
        "registries" => UpdateConfig::REGISTRY_WILDCARD,
        "directories" => directories,
      },
      user: user
    ).run
  end
end
