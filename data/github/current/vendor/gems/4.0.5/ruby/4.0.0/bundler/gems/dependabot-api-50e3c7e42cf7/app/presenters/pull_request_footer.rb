# frozen_string_literal: true

class PullRequestFooter
  AUTOMERGE_START = "[//]: # (dependabot-automerge-start)\n"
  AUTOMERGE_END = "[//]: # (dependabot-automerge-end)"

  AUTOMATICALLY_REBASE_PRS_TEXT = "Dependabot will resolve any conflicts with this PR as long as you "\
    "don't alter it yourself. You can also trigger a rebase manually by "\
    "commenting `@dependabot rebase`."

  MANUALLY_TRIGGER_REBASE_TEXT = "You can trigger a rebase of this PR by commenting `@dependabot rebase`."

  def initialize(update_job:, updated_dependencies:, outdated_ignore_conditions_removed:, grouped_update:)
    @update_job = update_job
    @updated_dependencies = updated_dependencies
    @outdated_ignore_conditions_removed = outdated_ignore_conditions_removed
    @grouped_update = grouped_update
  end

  def footer_text
    footer = ""

    footer += "#{compatibility_badge(updated_dependencies.first)}\n\n" if include_compatibility_badge?

    footer += "#{conflicts_text}\n\n"
    footer += "#{automerge_text}\n\n"
    footer += "---\n\n"

    footer += "#{ignore_condition_removed_comment}\n\n" if outdated_ignore_conditions_removed?

    footer + dependabot_commands_text
  end

  # TODO(@jurre): Can we remove this?
  def automerge_text
    AUTOMERGE_START + AUTOMERGE_END
  end

  private

  attr_reader :update_job, :updated_dependencies, :grouped_update

  def outdated_ignore_conditions_removed?
    @outdated_ignore_conditions_removed
  end

  def include_compatibility_badge?
    return false if Dependabot.enterprise?
    return false if Dependabot.proxima?
    return false unless updated_dependencies.count == 1
    return false unless updated_dependencies.first.previous_version

    !updated_dependencies.first.previous_version.match?(/^[0-9a-f]{40}$/)
  end

  def compatibility_badge(updated_dependency)
    querystring =
      "dependency-name=#{updated_dependency.name}"\
      "&package-manager=#{updated_dependency.package_manager}"\
      "&previous-version=#{updated_dependency.previous_version}"\
      "&new-version=#{updated_dependency.version}"

    ci_status_url = "https://dependabot-badges.githubapp.com/badges/"\
                    "compatibility_score?#{querystring}"

    "[![Dependabot compatibility score](#{ci_status_url})]"\
    "(https://docs.github.com/en/github/managing-security-vulnerabilities/"\
    "about-dependabot-security-updates#about-compatibility-scores)"
  end

  def conflicts_text
    if update_config.automatically_rebase_prs?
      AUTOMATICALLY_REBASE_PRS_TEXT
    else
      MANUALLY_TRIGGER_REBASE_TEXT
    end
  end

  def ignore_condition_removed_comment
    "**Note:** Dependabot was ignoring updates to this dependency, but "\
    "since you've updated it yourself we've started tracking it for you "\
    "again. 🤖"
  end

  def dependabot_commands_text
    msg =
      "<details>\n"\
      "<summary>Dependabot commands and options</summary>\n"\
      "<br />\n\n"\
      "#{CommandsPresenter.dependabot_commands_text(update_job, grouped_update: grouped_update)}\n\n"

    msg + "</details>"
  end

  def update_config
    @update_config ||= update_job.update_config
  end

  def account
    @account ||= update_job.update_config.repo.account
  end

  def repo
    @repo ||= update_job.update_config.repo
  end
end
