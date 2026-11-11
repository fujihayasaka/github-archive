# frozen_string_literal: true

class CommandsPresenter
  # rubocop:disable Metrics/MethodLength
  def self.dependabot_commands_text(update_job, grouped_update: false)
    update_config = update_job.update_config
    msg =
      "You can trigger Dependabot actions by commenting on this PR:\n"\
      "- `@dependabot rebase` will rebase this PR\n"\
      "- `@dependabot recreate` will recreate this PR, overwriting any edits "\
      "that have been made to it\n"\
      "- `@dependabot show <dependency name> ignore conditions` will show all of the ignore conditions "\
      "of the specified dependency\n"

    msg += if grouped_update
             "- `@dependabot ignore <dependency name> major version` will close this group update PR and "\
               "stop Dependabot creating any more for the specific dependency's major version (unless you "\
               "unignore this specific dependency's major version or upgrade to it yourself)\n"\
               "- `@dependabot ignore <dependency name> minor version` will close this group update PR and "\
               "stop Dependabot creating any more for the specific dependency's minor version (unless you "\
               "unignore this specific dependency's minor version or upgrade to it yourself)\n"\
               "- `@dependabot ignore <dependency name>` will close this group update PR and stop "\
               "Dependabot creating any more for the specific dependency (unless you unignore "\
               "this specific dependency or upgrade to it yourself)\n"\
               "- `@dependabot unignore <dependency name>` will remove all of the ignore conditions "\
               "of the specified dependency\n"\
               "- `@dependabot unignore <dependency name> <ignore condition>` will remove the ignore condition "\
               "of the specified dependency and ignore conditions\n"
           else
             "- `@dependabot ignore this major version` will close this PR and "\
               "stop Dependabot creating any more for this major version (unless you "\
               "reopen the PR or upgrade to it yourself)\n"\
               "- `@dependabot ignore this minor version` will close this PR and "\
               "stop Dependabot creating any more for this minor version (unless you "\
               "reopen the PR or upgrade to it yourself)\n"\
               "- `@dependabot ignore this dependency` will close this PR and stop "\
               "Dependabot creating any more for this dependency (unless you reopen "\
               "the PR or upgrade to it yourself)\n"
           end

    if update_job.security_updates_only?
      msg += "You can disable automated security fix PRs for this repo "\
             "from the [Security Alerts page]"\
             "(#{security_alerts_url(update_config)})."
    end

    msg
  end
  # rubocop:enable Metrics/MethodLength

  def self.security_alerts_url(update_config)
    update_config.repo.github_url + "/network/alerts"
  end
end
