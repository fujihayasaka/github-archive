# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module ChatopInfo
  extend ActiveSupport::Concern

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :info,
           /info\s+(?<nwo>.*)?/,
           "info NWO [--tenant TENANT] or info OWNER [--tenant TENANT] " \
           "- Retrieve a summary for the specified repo or account" do
      nwo = jsonrpc_params[:nwo]
      config = jsonrpc_params[:config]
      package_manager = jsonrpc_params[:package_manager]
      tenant = jsonrpc_params[:tenant]

      if nwo.to_i.to_s == nwo
        repo = Repo.find_by(github_id: nwo)
        return jsonrpc_failure "Repository: #{nwo} - not found." unless repo

        nwo = repo.full_name
        account = repo.account
        github_login = account.github_login
        repo_name = repo.name
      else
        github_login, repo_name = nwo.split("/")
        account = find_account!(github_login, tenant)
      end
      lines = [
        "Account: #{github_login} - GitHub ID: #{account.github_id}",
        "Account State: #{account.current_state}",
        "Installation ID: #{account.current_installation_id.inspect}",
      ]

      if repo_name
        repo ||= find_by_nwo!(nwo, tenant)

        lines += [
          "Repository: #{nwo} - GitHub ID: #{repo.github_id}",
          "Pausing status: #{repo_active_state_for(repo)}",
          "Runner Type: #{runner_summary_for(repo)}",
          security_updates_enablement_summary_for(repo),
        ]

        if repo.update_configs.any?
          lines += [
            "Configs:",
            "```",
            config_summary_for(repo, config, package_manager),
            "```",
          ]

          lines += if repo.update_jobs.any?
                     [
                       "Jobs:",
                       "```",
                       job_summary_for(repo, config, package_manager),
                       "```",
                     ]
                   else
                     ["No update jobs found!"]
                   end
        else
          lines += ["No update configs found!"]
        end

        lines += if repo.registries.any?
                   [
                     "Registries:",
                     "```",
                     registry_summary_for(repo),
                     "```",
                   ]
                 else
                   ["Registries: None"]
                 end

        lines += [
          "Activity Logs:",
          Activity::Splunk.new(repo: repo).table_url,
        ]
      else
        if account.repository_accesses.any?
          repo_scope = repo_access_scope(account)

          lines += [
            "Selected Repositories (#{repo_scope.count}):",
            "```", repo_access_summary_for(account, repo_scope), "```",
          ]
        end

        lines += ["```", repo_summary_for(account), "```"]

        lines += [
          "\nActivity Logs:",
          Activity::Splunk.new(account: account).table_url,
        ]
      end

      jsonrpc_success(lines.join("\n"))
    end
  end
  # rubocop:enable Metrics/BlockLength

  private

  def repo_active_state_for(repo)
    return "Paused at #{repo.paused_at}" if repo.paused?
    return "Active - Will pause after #{repo.will_pause_at}" if repo.recently_inactive?

    repo.active? ? "Active" : "Deactivated"
  end

  def runner_summary_for(repo)
    repository_settings = Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)

    # Dependabot now always runs on GitHub Actions
    "#{UpdateJob::RUNNER_ACTIONS} - (#{runner_type_clause_for(repository_settings)})"
  end

  def runner_type_clause_for(repository_settings)
    if repository_settings&.dependabot_self_hosted_enabled
      "Self-Hosted"
    else
      "GitHub-Hosted"
    end
  end

  def repo_summary_for(account)
    repo_scope = account.repos.
                 includes(:update_jobs).
                 order(:name).
                 limit(100)

    Terminal::Table.new do |t|
      t.headings = %w(nwo github_id jobs)
      t.rows = repo_scope.map do |repo|
        [
          repo.full_name,
          repo.github_id,
          repo.update_jobs.count,
        ]
      end
      t.align_column(1, :right)
      t.style = { border_top: false, border_bottom: false }
    end.to_s
  end

  # repo_access_scope returns a scope that lists repos for the
  # repository_accesses table
  def repo_access_scope(account)
    query = <<~SQL.squish
      LEFT JOIN #{Repo.table_name} ON #{Repo.table_name}.github_id = #{RepositoryAccess.table_name}.github_id
    SQL

    account.repository_accesses.
      select("#{Repo.table_name}.name, #{RepositoryAccess.table_name}.github_id").
      joins(query).
      order(:github_id).
      limit(250)
  end

  # repo_access_summary_for summarizes the repositories the given account has
  # access to.
  def repo_access_summary_for(account, repo_scope)
    Terminal::Table.new do |t|
      t.headings = %w(nwo github_id)
      t.rows = repo_scope.map do |r|
        [
          r.name.blank? ? "not available" : account.github_login + "/" + r.name,
          r.github_id,
        ]
      end
      t.align_column(1, :right)
      t.style = { border_top: false, border_bottom: false }
    end.to_s
  end

  # rubocop:disable Metrics/MethodLength
  def config_summary_for(repo, config_id, package_manager)
    config_scope = repo.update_configs.
                   order(id: :desc).
                   limit(Repo::MAXIMUM_CONFIGS_ALLOWED)
    if config_id
      config_scope = config_scope.where(id: config_id)
    elsif package_manager
      config_scope = config_scope.where(package_manager: package_manager)
    end

    headings = %w(
      id
      package_manager
      directory
      directories
      state
      schedule
      cron_expression
      version_updates_enabled?
      registry_names
      instance_size
      next_enqueue_at
      created_at
    )
    Terminal::Table.new do |t|
      t.headings = headings
      t.rows = config_scope.map do |uc|
        registry_names = if uc.all_registries?
                           "*"
                         else
                           uc.update_config_registries.map(&:registry_name).join(",")
                         end
        [
          uc.id,
          uc.package_manager,
          uc.directory,
          uc.directories,
          uc.current_state,
          uc.update_schedule,
          uc.update_schedule_cron_expression,
          uc.version_updates_enabled?,
          registry_names,
          uc.required_instance_size,
          uc.next_enqueue_at,
          uc.created_at,
        ]
      end
      t.align_column(1, :right)
      t.style = { border_top: false, border_bottom: false }
    end.to_s
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength
  def job_summary_for(repo, config_id, package_manager)
    job_scope = repo.update_jobs.
                includes(:update_config).
                includes(pull_request_transition: :pull_request).
                order(created_at: :desc).
                limit(50)
    if config_id
      job_scope = job_scope.where(update_configs: { id: config_id })
    elsif package_manager
      job_scope = job_scope.where(update_configs: {
                                    package_manager: package_manager,
                                  })
    end

    job_scope.group_by(&:update_config).map do |update_config, jobs|
      title = [
        "Update Config ID #{update_config.id} -",
        "#{update_config.package_manager},",
        "directory: #{update_config.directory},",
        "directories: #{update_config.directories},",
        "target_branch: #{update_config.target_branch || '(default branch)'}",
      ].join(" ")

      job_table_for(title, jobs)
    end.join("\n\n\n")
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength
  def job_table_for(title, jobs)
    Terminal::Table.new do |t|
      t.title = title
      t.headings = %w(
        id
        trigger_type
        state
        actions_workflow_run_id
        created_at
        last_transition_at
      )
      t.rows = jobs.map do |job|
        [
          job.id,
          trigger_info_for(job),
          job.current_state,
          job.actions? ? job.actions_workflow_run_id : nil,
          job.created_at,
          job.last_transition&.created_at,
        ]
      end
      t.align_column(1, :right)
      t.style = { border_top: false, border_bottom: false }
    end.to_s
  end
  # rubocop:enable Metrics/MethodLength

  def trigger_info_for(job)
    [
      job.trigger_type,
      UpdateJob::SECURITY_TRIGGER_TYPES.include?(job.trigger_type) ? "GitHub ID #{job.github_request_id}" : nil,
      job.current_dependency_group&.name,
      UpdateJob::REBASE_TRIGGER_TYPES.include?(job.trigger_type) ? "PR ##{pr_number_for(job)}" : nil,
    ].compact.join("\n")
  end

  def pr_number_for(job)
    return unless job.updating_a_pull_request?

    job.pull_request_transition.pull_request.github_number
  end

  def registry_summary_for(repo)
    Terminal::Table.new do |t|
      t.headings = %w(name type)
      t.rows = repo.registries.map do |registry|
        [
          registry.name,
          registry.registry_type,
        ]
      end
      t.align_column(1, :right)
      t.style = { border_top: false, border_bottom: false }
    end.to_s
  end

  def security_updates_enablement_summary_for(repo)
    return "Security Updates Enablement Unknown" if repo.security_updates_enabled.nil?
    return "Security Updates Enabled" if repo.security_updates_enabled?

    "Security Updates Disabled"
  end
end
# rubocop:enable Metrics/ModuleLength
