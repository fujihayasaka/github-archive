# frozen_string_literal: true

require "yaml"

class DryRunPresenter
  DEBUGGER_REPO = "https://github.com/github/dependabot-update-debugger"
  DEBUGGER_README = [DEBUGGER_REPO, "blob", "main", "README.md"].join("/")

  def initialize(update_job:)
    @update_job = update_job
    @update_config = @update_job.update_config
    @repo = @update_config.repo
  end

  def command
    cmd = "bin/dry-run.rb #{update_config.package_manager} \"#{repo.full_name}\"#{dry_run_options}"
    cmd = [cmd_args, cmd].reject(&:empty?).join("  ")
    [preamble, cmd].join
  end

  def cli_command
    json = ActiveModelSerializers::SerializableResource.new(@update_job, serializer: UpdateJobSerializerPrivate).to_json
    json = JSON.parse(json)["data"]["attributes"]
    json["source"]["commit"] = @update_job.base_commit_sha if @update_job.base_commit_sha
    { "job" => json }.to_yaml
  end

  private

  attr_reader :update_job, :update_config, :repo

  def preamble
    if repo.private? || local_config_variables.any?
      <<~DEBUGGER_PREAMBLE
        #{DEBUGGER_README}

      DEBUGGER_PREAMBLE
    else
      ""
    end
  end

  def cmd_args
    # FIXME: The dry-run script does not support dependency groups, nor do we have
    #        plans to add support. If we do this work, they should be added here.
    #        If opt to not support groups in the dry-run script, this can be removed.
    args = ""
    args += "IGNORE_CONDITIONS='#{JSON.dump(ignore_conditions)}' \\\n" if ignore_conditions.any?
    args += "SECURITY_ADVISORIES='#{JSON.dump(security_advisories)}' \\\n" if security_advisories.any?
    args += "LOCAL_CONFIG_VARIABLES='#{JSON.dump(local_config_variables)}' \\\n" if local_config_variables.any?
    args
  end

  def security_advisories
    # Find github security advisories for the job.dependencies
    @security_advisories ||= kebab_keys(update_job.relevant_security_advisories_hash)
  end

  def ignore_conditions
    @ignore_conditions ||= kebab_keys(update_job.ignore_conditions_hash)
  end

  def local_config_variables
    @local_config_variables ||= update_job.update_config.registries.map(&:serialized_credentials)
  end

  def target_branch
    if update_config.target_branch &&
       update_config.target_branch != repo.default_branch
      update_config.target_branch
    end
  end

  def enabled_job_experiments
    update_job.experiments.select { |_, value| value }.keys
  end

  def requirements_update_strategy
    if update_config.requirements_update_strategy
      update_config.requirements_update_strategy
    elsif update_config.lockfile_only?
      "lockfile_only"
    end
  end

  def dry_run_options # rubocop:disable Metrics/PerceivedComplexity
    options = " --dir=\"#{update_config.directory}\""
    options += " --branch=\"#{target_branch}\"" if target_branch
    options += " --dep=\"#{update_job.dependencies.join(',')}\"" if update_job.dependencies
    options += " --requirements-update-strategy=\"#{requirements_update_strategy}\"" if requirements_update_strategy
    options += " --security-updates-only" if update_job.security_updates_only?
    options += " --updater-options=#{enabled_job_experiments.join(',')}" if enabled_job_experiments.any?
    options += " --vendor-dependencies" if update_config.vendor?
    options += " --commit=#{update_job.base_commit_sha}" if update_job.base_commit_sha
    options += " --enable-beta-ecosystems" if update_job.beta_ecosystems_enabled?
    options + " --cache=files"
  end

  def kebab_keys(arr)
    arr.map { |hash| hash.compact.transform_keys { |key| key.to_s.dasherize } }
  end
end
