# typed: true
# frozen_string_literal: true

module SecurityAnalysisDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { User }

  DEPENDENCY_GRAPH_NEW_REPOS_KEY = "dependency_graph.new_repos_enable"
  SECURITY_ALERTS_NEW_REPOS_KEY = "security_alerts.new_repos_enable"
  VULNERABILITY_UPDATES_NEW_REPOS_KEY = "vulnerability_updates.new_repos_enable"
  VULNERABILITY_UPDATES_GROUPING_NEW_REPOS_KEY = "vulnerability_updates_grouping.new_repos_enable"
  DEPENDABOT_ON_ACTIONS_NEW_REPOS_KEY = "dependabot_on_actions.new_repos_enable"
  DEPENDABOT_SELF_HOSTED_NEW_REPOS_KEY = "dependabot_self_hosted.new_repos_enable"
  DEPENDABOT_AUTOFIX_NEW_REPOS_KEY = "dependabot_autofix.new_repos_enable"
  SECRET_SCANNING_NEW_REPOS_KEY = "secret_scanning.new_repos_enable"
  PRIVATE_VULNERABILITY_REPORTING_NEW_REPOS_KEY = "private_vulnerability_reporting.new_repos_enable"
  CODE_SCANNING_RECOMMEND_EXTENDED_QUERY_SUITE_KEY = "code_scanning_default_setup.recommend_extended_query_suite"
  INNERSOURCE_ADVISORIES_NEW_REPOS_KEY = T.let("innersource_advisories.new_repos_enable", String)

  # Dependency graph
  # Note: For public repos, dependency graph is enabled by default.

  # Enable dependency graph for all new private repos in an organization.
  def enable_dependency_graph_for_new_repos(actor:)
    config.enable(DEPENDENCY_GRAPH_NEW_REPOS_KEY, actor)
  end

  # Disable dependency_graph for all new private repos in an organization.
  # This will also disable dependabot alerts and security updates for new repos in the organization.
  def disable_dependency_graph_for_new_repos(actor:)
    config.delete(DEPENDENCY_GRAPH_NEW_REPOS_KEY, actor)
    disable_security_alerts_for_new_repos(actor: actor)
  end

  # Indicates if dependency graph was enabled for all new private repos from the organization level Security & analysis page.
  def dependency_graph_enabled_for_new_repos?
    config.enabled?(DEPENDENCY_GRAPH_NEW_REPOS_KEY)
  end

  # Dependabot alerts

  # Enable dependabot alerts for all new repos in an organization.
  # This will also enable dependency graph for all new private repos in the organization.
  def enable_security_alerts_for_new_repos(actor:)
    config.enable(SECURITY_ALERTS_NEW_REPOS_KEY, actor)
    enable_dependency_graph_for_new_repos(actor: actor)
  end

  # Disable dependabot alerts for all new repos in an organization.
  # This will also disable dependabot security updates for all new repos in the organization.
  def disable_security_alerts_for_new_repos(actor:)
    config.delete(SECURITY_ALERTS_NEW_REPOS_KEY, actor)
    disable_vulnerability_updates_for_new_repos(actor: actor)
  end

  # Indicates if dependabot alerts was enabled for all new repos from the organization level Security & analysis page.
  def security_alerts_enabled_for_new_repos?
    config.enabled?(SECURITY_ALERTS_NEW_REPOS_KEY)
  end

  # Dependabot security updates

  # Enable dependabot security updates for all new repos in an organization.
  # This will also enable dependency graph and dependabot alerts for all new repos in the organization.
  def enable_vulnerability_updates_for_new_repos(actor:)
    config.enable(VULNERABILITY_UPDATES_NEW_REPOS_KEY, actor)
    enable_security_alerts_for_new_repos(actor: actor)
  end

  # Disable dependabot security updates for all new repos in an organization.
  def disable_vulnerability_updates_for_new_repos(actor:)
    config.delete(VULNERABILITY_UPDATES_NEW_REPOS_KEY, actor)
  end

  # Indicates if dependabot security updates was enabled for all new repos from the organization level Security & analysis page.
  def vulnerability_updates_enabled_for_new_repos?
    config.enabled?(VULNERABILITY_UPDATES_NEW_REPOS_KEY)
  end

  # Enable dependabot security updates grouping for all new repos in an organization.
  # This will also enable dependency graph, dependabot alerts and dependabot updates for all new repos in the organization.
  def enable_vulnerability_updates_grouping_for_new_repos(actor:)
    config.enable(VULNERABILITY_UPDATES_GROUPING_NEW_REPOS_KEY, actor)
    enable_vulnerability_updates_for_new_repos(actor: actor)
  end

  # Disable grouped security updates for all new repos in an organization.
  def disable_vulnerability_updates_grouping_for_new_repos(actor:)
    config.delete(VULNERABILITY_UPDATES_GROUPING_NEW_REPOS_KEY, actor)
  end

  # Indicates if grouped security updates was enabled for all new repos from the organization level Security & analysis page.
  def vulnerability_updates_grouping_enabled_for_new_repos?
    config.enabled?(VULNERABILITY_UPDATES_GROUPING_NEW_REPOS_KEY)
  end

  # Dependabot on Actions
  # Enable dependabot on actions for all new repos in an organization.
  def enable_dependabot_on_actions_for_new_repos(actor:)
    config.enable(DEPENDABOT_ON_ACTIONS_NEW_REPOS_KEY, actor)
  end

  def disable_dependabot_on_actions_for_new_repos(actor:)
    config.delete(DEPENDABOT_ON_ACTIONS_NEW_REPOS_KEY, actor)
  end

  def dependabot_on_actions_enabled_for_new_repos?
    config.enabled?(DEPENDABOT_ON_ACTIONS_NEW_REPOS_KEY)
  end

  def enable_dependabot_self_hosted_for_new_repos(actor:)
    config.enable(DEPENDABOT_SELF_HOSTED_NEW_REPOS_KEY, actor)
  end

  def disable_dependabot_self_hosted_for_new_repos(actor:)
    config.delete(DEPENDABOT_SELF_HOSTED_NEW_REPOS_KEY, actor)
  end

  def dependabot_self_hosted_enabled_for_new_repos?
    config.enabled?(DEPENDABOT_SELF_HOSTED_NEW_REPOS_KEY)
  end

  # Dependabot Autofix
  def dependabot_autofix_enabled_for_new_repos?
    config.enabled?(DEPENDABOT_AUTOFIX_NEW_REPOS_KEY)
  end

  def enable_dependabot_autofix_for_new_repos(actor:)
    config.enable(DEPENDABOT_AUTOFIX_NEW_REPOS_KEY, actor)
  end

  def disable_dependabot_autofix_for_new_repos(actor:)
    config.delete(DEPENDABOT_AUTOFIX_NEW_REPOS_KEY, actor)
  end

  # Private vulnerability reporting

  def enable_private_vulnerability_reporting_for_new_repos(actor:)
    config.enable(PRIVATE_VULNERABILITY_REPORTING_NEW_REPOS_KEY, actor)
  end

  def disable_private_vulnerability_reporting_for_new_repos(actor:)
    config.delete(PRIVATE_VULNERABILITY_REPORTING_NEW_REPOS_KEY, actor)
  end

  def private_vulnerability_reporting_enabled_for_new_repos?
    config.enabled?(PRIVATE_VULNERABILITY_REPORTING_NEW_REPOS_KEY)
  end

  # Code scanning default setup -- recommend 'extended' query suite

  def enable_code_scanning_recommend_extended_query_suite(actor:)
    config.enable(CODE_SCANNING_RECOMMEND_EXTENDED_QUERY_SUITE_KEY, actor)
  end

  def disable_code_scanning_recommend_extended_query_suite(actor:)
    config.delete(CODE_SCANNING_RECOMMEND_EXTENDED_QUERY_SUITE_KEY, actor)
  end

  def code_scanning_recommend_extended_query_suite?
    config.enabled?(CODE_SCANNING_RECOMMEND_EXTENDED_QUERY_SUITE_KEY)
  end

  # Innersource Advisories
  def enable_innersource_advisories_for_new_repos(actor:)
    config.enable(INNERSOURCE_ADVISORIES_NEW_REPOS_KEY, actor)
  end

  def disable_innersource_advisories_for_new_repos(actor:)
    config.delete(INNERSOURCE_ADVISORIES_NEW_REPOS_KEY, actor)
  end

  def innersource_advisories_enabled_for_new_repos?
    config.enabled?(INNERSOURCE_ADVISORIES_NEW_REPOS_KEY)
  end
end
