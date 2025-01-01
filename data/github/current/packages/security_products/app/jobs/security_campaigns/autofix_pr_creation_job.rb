# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class AutofixPrCreationJob < ApplicationJob
    include CodeScanning::AlertDependency

    queue_as :security_campaigns

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    class Alert < T::Struct
      prop :number, Integer
      prop :turboscan_result, T.nilable(Turboscan::Proto::Result)
      prop :suggested_fix_state, T.nilable(Turboscan::Proto::RepoSuggestedFixState)
      prop :repository, Repository
    end

    sig { params(campaign_id: Integer).void }
    def perform(campaign_id:)
      return if GitHub.enterprise?
      return if GitHub.flipper[:security_campaigns_disable_autofix_pr_creation_job].enabled?

      campaign = SecurityCampaigns::SecurityCampaign.published.find_by(id: campaign_id)
      return if campaign.nil?
      return unless SecurityCampaigns.autofix_pr_creation_enabled?(T.must(campaign.organization))

      alerts = build_alerts_for(campaign:)
      alerts = alerts.sort_by { |alert| [alert.repository.id, alert.number] }
      alerts.filter! do |alert|
        alert.repository.present? && CodeScanning::Autofix.any_enabled_for_repo?(alert.repository)
      end

      alerts.filter! do |alert|
        alert.turboscan_result.present? && CodeScanning::Autofix.enabled_for_tool?(alert.repository, T.must(alert.turboscan_result&.tool).name)
      end

      add_suggested_fix_states(alerts:, campaign:)

      # Filter alerts to only those who have valid autofixes
      alerts.filter! do |alert|
        state = alert.suggested_fix_state&.state
        state = Turboscan::Proto::SuggestedFixAlertState.resolve(state) if state.is_a?(Symbol)

        if state != Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID || state != Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP
          GitHub.logger.info(
            "Security campaign automatic autofix PR creation one alert has no valid fix",
            "gh.organization.id" => campaign.organization_id,
            "gh.security_campaign.id" => campaign.id,
            "gh.alert_number" => alert.number,
            "gh.repository.id" => alert.repository.id,
            "gh.suggested_fix_state" => Turboscan::Proto::SuggestedFixAlertState.lookup(T.must(state)),
          )
        end
        state == Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID || state == Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP
      end

      # Retrieve alert links and filter alerts to only those that have no alert link
      alert_links = alert_links(alerts:, campaign:)
      alert_links_by_repo_and_number = alert_links.index_by { |s| [s.repository_id, s.alert_number] }
      alerts.filter! do |alert|
        alert_links_by_repo_and_number[[alert.repository.id, alert.number]].nil?
      end

      bot = SecurityCampaigns.bot!

      GitHub.logger.info(
        "Security campaign automatic autofix PR creation starting",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.security_campaign.alerts_size" => alerts.size,
      )

      alerts_by_repo = T.let(alerts.group_by { |alert| alert.repository }, T::Hash[Repository, T::Array[Alert]])
      alerts_by_repo.each do |repo, repo_alerts|
        default_branch_ref = repo.default_branch_ref
        head_commit_oid = default_branch_ref.commit.oid

        begin
          autofix_suggestions = T.let(CodeScanning::AutofixSuggestion.fetch_applicable_suggested_fix_alerts(
            repository: repo,
            alert_numbers: repo_alerts.map(&:number),
            head_commit_oid:,
          ), T::Hash[Integer, Turboscan::Proto::SuggestedFixAlert])
        rescue CodeScanning::AutofixError => e
          GitHub.logger.info(
            "Security campaign automatic autofix PR creation failed fetching valid autofix suggestions for repo: #{e}",
            "gh.organization.id" => campaign.organization_id,
            "gh.security_campaign.id" => campaign.id,
            "gh.repository.id" => repo.id,
          )
          next
        end

        # Only create autofixes for alerts that have autofix suggestions
        repo_alerts.filter! do |alert|
          autofix_suggestions.key?(alert.number)
        end

        # For now, we only use 1 autofix, so just select a random one.
        alert = repo_alerts.first
        if alert.nil?
          GitHub.logger.info(
            "Security campaign automatic autofix PR creation: no alerts with valid autofix suggestion in repository",
            "gh.organization.id" => campaign.organization_id,
            "gh.security_campaign.id" => campaign.id,
            "gh.repository.id" => repo.id
          )
          next
        end
        autofix_suggestion = CodeScanning::AutofixSuggestion.new(T.must(autofix_suggestions[alert.number]).suggested_fix)

        alert_number = alert.number
        alert_url = UrlHelpers.repository_code_scanning_result_url(repo.owner, repo, number: alert.number, host: GitHub.url)

        branch_name = "campaign-#{campaign.number}-autofixes-for-alert-#{alert_number}"
        # Create a new branch for the autofix
        branch = repo.heads.find(branch_name)
        if branch.present?
          GitHub.logger.info(
            "Security campaign automatic autofix PR creation: branch already exists",
            "gh.organization.id" => campaign.organization_id,
            "gh.security_campaign.id" => campaign.id,
            "gh.repository.id" => repo.id,
            "gh.branch.name" => branch_name,
          )
          next
        end
        branch = repo.heads.create(branch_name, head_commit_oid, bot)

        pull_request = with_write do
          # Execute all actions on the PR as the bot instead of as the user that originally created the campaign
          GitHub.context.push(actor_id: bot.id) do
            # Commit autofix to branch
            CodeScanning::AutofixCommit.create(
              alert_number:,
              commit_message: nil,
              repository: repo,
              ref: branch,
              author: bot,
              suggested_fix: autofix_suggestion,
              reflog_via: "security campaign automatic autofix PR creation"
            )

            # Create PR for the autofix
            PullRequest.create_for!(repo, {
              user: bot,
              base: repo.default_branch,
              head: branch.name,
              title: CodeScanning::AutofixCommit.message_for_alert(alert_number:, alert_title: alert_title(alert.turboscan_result)),
              body: CodeScanning::AutofixCommit.pull_request_description_for_alert(repository: repo, alert_number:, suggested_fix: autofix_suggestion, security_campaign: campaign),
            })
          end
        end

        # Create alert links
        GitHub::Turboscan.create_alert_links(
          repository_id: repo.id,
          links: [
            {
              alert_number: alert_number,
              pull_request_id: pull_request.id,
            }
          ]
        )

        GitHub.logger.info(
          "Security campaign automatic autofix PR created",
          "gh.organization.id" => campaign.organization_id,
          "gh.security_campaign.id" => campaign.id,
          "gh.repository.id" => repo.id,
          "gh.pull_request.id" => pull_request.id,
          "gh.pull_request.number" => pull_request.number,
          "gh.alert_number" => alert_number,
        )
      end
    end

    private

    sig { params(campaign: SecurityCampaigns::SecurityCampaign).returns(T::Array[Alert]) }
    def build_alerts_for(campaign:)
      turboscan_alerts = SecurityCampaigns::TurboscanHelper.alerts_by(campaign:)
      campaign_repos = T.must(campaign.organization).repositories.where(id: turboscan_alerts.map { |a| a.repository_id }).index_by(&:id)
      turboscan_alerts.map do |turboscan_result|
        repository = campaign_repos[turboscan_result.repository_id]
        Alert.new(
          number: T.must(turboscan_result.result).number,
          repository:,
          turboscan_result: T.must(turboscan_result.result)
        )
      end
    end

    sig { params(alerts: T::Array[Alert], campaign: SecurityCampaigns::SecurityCampaign).void }
    def add_suggested_fix_states(alerts:, campaign:)
      suggested_fix_states = SecurityCampaigns::TurboscanHelper.suggested_fix_states_by(campaign:)
      suggested_fix_states_by_repo_and_number = suggested_fix_states.index_by { |s| [s.repository_id, s.alert_number] }
      alerts.each do |alert|
        alert.suggested_fix_state = suggested_fix_states_by_repo_and_number[[alert.repository.id, alert.number]]
      end
    end

    sig { params(alerts: T::Array[Alert], campaign: SecurityCampaigns::SecurityCampaign).returns(T::Array[Turboscan::Proto::AlertLink]) }
    def alert_links(alerts:, campaign:)
      repo_numbers = alerts.map do |alert|
        Turboscan::Proto::RepoNumber.new(
          repository_id: alert.repository.id,
          number: alert.number,
        )
      end
      SecurityCampaigns::TurboscanHelper.alert_links_for(repo_numbers:)
    end
  end
end
