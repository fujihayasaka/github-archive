# typed: true
# frozen_string_literal: true

module AuditLog
  class AuditLogEntryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::TagHelper
    include CommentsHelper
    include AvatarHelper
    include GitHub::TokenScanning::SecretScanningHelper
    include UrlHelpers
    include EnterpriseManagedUsersHelper
    attr_reader :entry, :view

    LINKABLE_KEYS = %i[
      actor
      actor_id
      admins
      admin_ids
      deploy_key_fingerprint
      org
      org_id
      repo
      repo_id
      user
      user_id
      staff_actor
      staff_actor_id
      issue_id
      issue_comment_id
      pull_request_id
      review_id
      pull_request
      comment_id
      commit_comment_id
    ]
    def initialize(entry, view = nil)
      @entry = entry
      @view = view
    end

    def explanation
      case entry.hit.data[:explanation]
      when "stale"
        "was marked as stale"
      when "new_hire"
        "was unverified during the GitHub onboarding process"
      when "password_changed"
        "due to password changed"
      when "password_reset"
        "due to password reset"
      when "password_randomized"
        "due to password randomized"
      end
    end

    def linkable_key?(key)
      LINKABLE_KEYS.include? key
    end

    def pretty_metadata
      JSON.pretty_generate Hash[entry_details]
    end

    def entry_details
      prepared_entry = entry.hit.merge!(entry.hit.data)
        .sort
        .to_h
        .tap do |h|
          h["@timestamp"] = entry.timestamp(Time.at(h["@timestamp"] / 1000)) if h["@timestamp"]
          h["created_at"] = entry.timestamp(Time.at(h["created_at"] / 1000)) if h["created_at"]
        end

      if GitHub.enterprise?
        if view.can_show_ip? && entry.ip_safe_action?
          prepared_entry
        else
          prepared_entry.reject { |k, _| k == "actor_ip" }
        end
      else
        action = entry.hit.action
        prefix = action.split(".")[0]
        fields = [].concat(Audit::Fields::LISTS[action] || Audit::Fields::LISTS[prefix] || Audit::Fields::LISTS["default"])
        if view.can_show_ip? && entry.ip_safe_action?
          fields << "actor_ip" unless fields.include?("actor_ip")
        end
        prepared_entry.select { |k, _| fields.uniq.include?(k) }
      end
    end

    def link_to_blocked_user
      helpers.link_to(entry.hit.data[:blocked_user], "/#{entry.hit.data[:blocked_user]}")
    end

    def display_user_avatar?
      !entry.own_entry? && !entry.user_id.nil? && entry.org_id != entry.user_id
    end

    def team_name
      entry.hit.data[:team] && entry.hit.data[:team].split("/").last
    end

    def visibility
      entry.hit.data[:visibility] || entry.hit.data[:access]
    end

    def previous_visibility
      entry.hit.data[:previous_visibility]
    end

    def team_access
      entry.hit.data[:permission] && Team::PERMISSIONS_TO_ABILITIES[entry.hit.data[:permission]]
    end

    def old_team_access
      entry.hit.data[:old_permission] && Team::PERMISSIONS_TO_ABILITIES[entry.hit.data[:old_permission]]
    end

    def permission
      entry.hit.data[:permission]
    end

    def access_token_name
      entry.hit[:user_programmatic_access_name]
    end

    RESOURCE_PARENTS_WITH_NAMES = {
      User         => "account",
      Organization => "organization",
      Repository   => "repository",
    }.freeze

    def access_token_permissions_added_explanation
      permissions_added = entry.hit[:permissions_added] || {}
      return "no permissions" if permissions_added.empty?

      RESOURCE_PARENTS_WITH_NAMES.each_with_object([]) do |(resource_parent, name), array|
        permissions_granted = "#{resource_parent}::Resources".constantize.filter(permissions_added)
        next if permissions_granted.none?

        count = permissions_granted.count
        array << "#{count} #{name} #{'permission'.pluralize(count)}"
      end.to_sentence
    end

    def access_token_resource_owner_name
      return unless entry.hit[:user_programmatic_access_id].present?
      return entry.hit[:org] if entry.hit[:org].present?

      if entry.hit[:user].present? && entry.hit[:user] == entry.hit[:actor]
        "yourself"
      else
        entry.hit[:user]
      end
    end

    def team_name_was
      "#{entry.hit[:org]}/#{entry.hit.data[:name_was]}"
    end

    REMOVE_MEMBER_REASONS_HASH = {
      Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE => "2fa non-compliance",
      Organization::RemovedMemberNotification::SAML_EXTERNAL_IDENTITY_MISSING => "SAML external identity missing",
      Organization::RemovedMemberNotification::TWO_FACTOR_ACCOUNT_RECOVERY => "account recovery due to 2fa lockout",
      Organization::RemovedMemberNotification::USER_ACCOUNT_DELETED => "user account deletion",
    }.with_indifferent_access.freeze

    # returns the reason why a member was removed from an organization
    #
    # Returns nil or a string
    def remove_member_reason
      REMOVE_MEMBER_REASONS_HASH[entry.hit.data["reason"]]
    end

    def remove_member_reason_text
      reason = remove_member_reason
      return "" unless reason.present?

      hit_reason = entry.hit.data["reason"]

      conjunction = "for"
      if hit_reason == Organization::RemovedMemberNotification::USER_ACCOUNT_DELETED
        conjunction = "on"
      end

      "#{conjunction} #{reason}"
    end

    def remove_member_verb_text
      if entry.own_entry?
        "removed themselves"
      else
        "was removed"
      end
    end

    def team_privacy
      normalized_team_privacy(entry.hit.data[:privacy])
    end

    def team_privacy_was
      normalized_team_privacy(entry.hit.data[:privacy_was])
    end

    def link_to_parent_team
      parent_team_id = entry.hit.data[:parent_team_id]

      if parent_team_id.nil?
        "root"
      elsif parent_team = Team.find_by(id: parent_team_id)
        helpers.link_to(parent_team.name, "/orgs/#{entry.hit[:org]}/teams/#{parent_team.name}")
      else
        "[team not found]"
      end
    end

    def link_to_parent_team_was
      parent_team_id_was = entry.hit.data[:parent_team_id_was]

      if parent_team_id_was.nil?
        "root"
      elsif parent_team = Team.find_by(id: parent_team_id_was)
        helpers.link_to(parent_team.name, "/orgs/#{entry.hit[:org]}/teams/#{parent_team.name}")
      else
        "[team not found]"
      end
    end

    def link_to_org_team(team = nil)
      if team.nil?
        helpers.link_to(entry.hit.data[:team], "/orgs/#{entry.hit[:org]}/teams/#{team_name}")
      else
        helpers.link_to(team, "/orgs/#{entry.hit[:org]}/teams/#{team}")
      end
    end

    def link_to_enterprise_team(team = nil)
      if team.nil?
        helpers.link_to(entry.hit.data[:team], urls.enterprise_team_path(slug: entry.hit[:business].to_s, team_slug: team_name.to_s))
      else
        helpers.link_to(team, urls.enterprise_team_path(slug: entry.hit[:business].to_s, team_slug: team))
      end
    end

    def link_to_team(team = nil)
      if entry.hit[:team_type] == "enterprise"
        link_to_enterprise_team(team)
      else
        link_to_org_team(team)
      end
    end

    def actor_is_business?
      business? && entry.business_id == entry.actor_id
    end

    def actor_is_org?
      org? && entry.org_id == entry.actor_id
    end

    def actor_is_user?
      entry.user_id == entry.actor_id
    end

    def actor_is_sponsor?
      return @actor_is_sponsor if defined?(@actor_is_sponsor)
      @actor_is_sponsor = entry.hit[:sponsor_id].present? &&
        entry.hit[:sponsor_id] == entry.hit[:actor_id]
    end

    def link_to_sponsor
      return unless entry.hit[:sponsor].present?
      link_to_user(entry.hit[:sponsor])
    end

    def link_to_actor
      link_to_user(entry.hit[:actor])
    end

    # Public: Get a link to view a model in the GitHub Models Marketplace, if this audit log event involved one.
    def link_to_model
      return unless GitHub.models_enabled?
      if (slug = entry.hit[:model_key]).present?
        registry, model_name = GitHubModels.domain.models.registry_and_name_from_slug(slug)
        if registry && model_name
          if GitHub.marketplace_enabled?
            helpers.link_to(entry.hit[:model].presence || model_name,
              urls.marketplace_model_path(registry, model_name))
          else
            entry.hit[:model].presence || model_name
          end
        else
          entry.hit[:model].presence || slug
        end
      end
    end

    # Get a link to a specific user.
    #
    # If user is provided blank, first check the entry's `user_id` field, then the `user` field for the user.
    #
    # user - String or User object representing the user to link to, or nil by default.
    #
    # Returns String or nil.
    def link_to_user(user = nil)
      subject =
        if user.blank? && entry.user.present?
          entry.user
        elsif user ||= entry.hit[:user]
          user
        end
      return unless subject

      name = subject.respond_to?(:display_login) ? subject.display_login : subject

      helpers.link_to(name, urls.user_path(subject))
    end

    def link_to_integration_manager
      manager = entry.hit.data[:manager]
      return if manager.blank?

      # TODO: Audit log should include manager_type field to avoid string parsing.
      # Currently no type field exists, so we rely on string pattern matching to distinguish between users and teams.
      if manager.start_with?("/ent:")
        enterprise_team_slug = manager.sub("/", "")
        case integration&.owner
        when Business
          link_to_enterprise_team(enterprise_team_slug)
        when Organization
          link_to_team(enterprise_team_slug)
        else
          # This should be unreachable - integration owner must be Business or Organization
          manager
        end
      elsif manager.start_with?("#{org_name}/")
        team_slug = manager.split("/").last
        helpers.link_to(manager, "/orgs/#{org_name}/teams/#{team_slug}")
      else
        link_to_user(manager)
      end
    end

    def business?
      entry.hit[:business].present?
    end

    def org?
      entry.hit[:org].present?
    end

    def link_to_org(organization = entry.hit[:org])
      helpers.link_to(organization, "/#{organization}")
    end

    def link_to_project
      project = entry.project
      if project && project.owner.present?
        link_text = project_name ? project_name : "##{project.number}"
        helpers.link_to(link_text, urls.project_path(project))
      else
        "##{project_id}"
      end
    end

    def link_to_project_collaborator
      collaborator_type = entry.hit[:collaborator_type]
      collaborator = entry.hit[:collaborator]

      return nil unless collaborator

      unless collaborator_type == "team"
        return link_to_user(collaborator)
      end

      project = entry.project
      team_name = collaborator.split("/").last
      if team_name && project && project.owner.present? && project.owner.is_a?(Organization)
        return helpers.link_to(team_name, "/orgs/#{project.owner.display_login}/teams/#{team_name}")
      end

      nil
    end

    def old_project_base_role
      entry.hit.data[:old_project_base_role]
    end

    def new_project_base_role
      entry.hit.data[:new_project_base_role]
    end

    def project_role
      entry.hit[:project_role]
    end

    def old_project_role
      entry.hit[:old_project_role]
    end

    def link_to_business(business = entry.hit[:business])
      helpers.link_to(business, urls.enterprise_path(business))
    end

    def renamed_project
      entry.hit.data["old_name"]
    end

    def project_id
      entry.hit.data["project_id"]
    end

    def project_name
      entry.hit.data["project_name"]
    end

    def repo?
      entry.hit[:repo].present?
    end

    def integration?
      entry.hit[:integration].present?
    end

    def link_to_pull_request
      pull_id = entry.hit[:pull_request_id]
      if pull_id && pull = PullRequest.find_by(id: pull_id)
        helpers.link_to(T.must(pull.repository).name_with_display_owner + " ##{pull.number}", pull.permalink(include_host: false))
      else
        "[unknown pull request]"
      end
    end

    def link_to_pull_request_review
      review_id = entry.hit[:review_id]
      if review_id && review = PullRequestReview.find_by(id: review_id)
        helpers.link_to("review of #{T.must(review.repository).name_with_display_owner} ##{T.must(review.pull_request).number}", review.permalink(include_host: false))
      else
        "review (#{review_id ? review_id : 'unknown'})"
      end
    end

    def link_to_pull_request_review_comment
      comment_id = entry.hit[:comment_id]
      if comment_id && comment = PullRequestReviewComment.find_by(id: comment_id)
        helpers.link_to(
          "review comment on #{T.must(comment.repository).name_with_display_owner} ##{T.must(comment.pull_request).number}",
          comment.permalink(include_host: false),
        )
      else
        "review comment (#{comment_id ? comment_id : 'unknown'})"
      end
    end

    def link_to_user_or_team
      reviewer_type = entry.hit[:reviewer_type]
      if reviewer_type == "User"
        link_to_user(entry.hit[:reviewer])
      elsif reviewer_type == "Team"
        org, team = entry.hit[:reviewer].split("/")
        helpers.link_to(entry.hit.data[:reviewer], "/orgs/#{org}/teams/#{team}")
      end
    end

    def link_to_repo
      return link_to_repo_from_id unless entry.hit[:repo]
      helpers.link_to(entry.hit[:repo], "/#{entry.hit[:repo]}")
    end

    def link_to_repo_from_id
      repo_id = entry.hit[:repo_id]

      return if repo_id.nil?
      repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        Repositories.domain.by_id(repo_id)
      else
        Repository.find_by(id: repo_id)
      end
      if repo
        helpers.link_to(repo.name_with_display_owner, "/#{repo.name_with_display_owner}")
      else
        "[unknown repo]"
      end
    end

    def link_to_advisory
      repo = entry.hit[:repo]
      ghsa_id = entry.hit[:ghsa_id] || entry.hit[:repository_advisory]

      if repo
        helpers.link_to(ghsa_id, "/#{repo}/security/advisories/#{ghsa_id}")
      else
        helpers.link_to(ghsa_id, "/advisories/#{ghsa_id}")
      end
    end

    def link_to_advisory_credit_recipient
      link_to_user(entry.hit[:recipient] || "ghost")
    end

    def exported_repos_list
      helpers.safe_join(Array(entry.hit[:repo]), ", ")
    end

    def authorized_actors_list
      actors = entry.hit[:authorized_actors] || []
      return "admins only" if actors.empty?
      helpers.safe_join(Array(actors), ", ")
    end

    def migration_id
      entry.hit.data[:migration_id]
    end

    def link_to_hook_target?
      # special handling for pre-existing global hook audit log entries
      return true if GitHub.single_business_environment? && entry.hit.data[:hook_type] == "global"
      [
        :repo,
        :org,
        :business,
        :sponsors_listing_id,
        :integration,
      ].any? { |t| entry.hit[t].present? }
    end

    def link_to_resource_owner
      if GitHub.sponsors_enabled? && entry.hit[:sponsors_listing_id]
        link_to_sponsors_listing
      elsif entry.hit[:integration]
        link_to_integration
      elsif entry.hit[:repo]
        link_to_repo
      elsif entry.hit[:org]
        link_to_org
      elsif entry.hit[:business]
        link_to_business
      elsif entry.hit.data[:hook_type] == "global" && GitHub.single_business_environment?
        # special handling for pre-existing global hook audit log entries
        link_to_business(GitHub.global_business.slug)
      elsif entry.hit[:user]
        link_to_user
      end
    end

    def link_to_sponsors_listing
      helpers.link_to(sponsor_listing_owner, sponsorable_dashboard_path(sponsorable_id: sponsor_listing_owner))
    end

    def sponsorable_org?
      return true if entry.hit[:sponsorable_org].present?
      return false if entry.hit[:sponsorable_user].present?
      entry.hit[:org].present?
    end

    def sponsorable_org
      entry.hit[:sponsorable_org] || entry.hit[:org]
    end

    def sponsorable_user
      entry.hit[:sponsorable_user] || entry.hit[:user]
    end

    def link_to_oauth_application
      helpers.link_to(entry.hit.data[:oauth_application], "/organizations/#{entry.hit[:org]}/settings/applications/#{entry.hit.data[:oauth_application_id]}")
    end

    def link_to_integration
      return entry.hit[:integration] unless integration

      path = if integration.synchronized_dotcom_app?
        T.unsafe(self).third_party_app_path(integration)
      else
        urls.gh_app_path(integration, integration.owner)
      end

      helpers.link_to(integration_name, path)
    end

    def link_to_integration_settings
      return entry.hit[:integration] unless integration
      return link_to_integration if integration.synchronized_dotcom_app?

      helpers.link_to(integration_name, urls.gh_settings_app_path(integration))
    end

    def link_to_installation
      return entry.hit[:integration] unless installation
      helpers.link_to(integration_name, urls.gh_settings_installation_path(installation))
    end

    def integration_name
      integration&.name
    end

    def link_to_integration_transfer_recipient
      helpers.link_to(entry.hit.data[:transfer_to], "/#{entry.hit.data[:transfer_to]}")
    end

    def installation_repositories_added_automatically?
      entry.hit.data.fetch(:added_automatically, false)
    end

    def integration_installed_automatically?
      entry.hit.data.fetch(:installed_automatically, false)
    end

    def link_to_repo_hook
      helpers.link_to(safe_hook_name,
        "/#{entry.hit[:repo]}/settings/hooks/#{entry.hit.data[:hook_id]}")
    end

    def link_to_repository_name(val)
      helpers.link_to(val, "/#{val}")
    end

    def link_to_org_hook
      helpers.link_to(safe_hook_name,
        "/organizations/#{entry.hit[:org]}/settings/hooks/#{entry.hit.data[:hook_id]}")
    end

    def link_to_business_hook(business = entry.hit[:business])
      helpers.link_to(safe_hook_name, urls.hook_enterprise_path(business, entry.hit.data[:hook_id]))
    end

    def alert_resolution_to_description
      resolution_description(entry.hit[:resolution])
    end

    def previous_validity
      entry.hit[:previous_validity]
    end

    def current_validity
      entry.hit[:current_validity]
    end

    def validity_changed_description
      if previous_validity.blank? || current_validity.blank?
        return ""
      end
      "Validity changed from #{previous_validity} to #{current_validity}."
    end

    def secret_type_display_name
      entry.hit[:secret_type_display_name]
    end

    def secret_type_provider
      entry.hit[:secret_type_provider]
    end

    def push_protection_setting
      entry.hit[:push_protection_setting]
    end

    def report_result
      entry.hit[:report_result]
    end

    def reported_token_label
      if secret_type_display_name.blank?
        return "token"
      end
      secret_type_display_name
    end

    def reported_token_provider_name
      if secret_type_provider.blank?
        return "provider"
      end
      secret_type_provider
    end

    def report_result_description
      if report_result.blank?
        return ""
      end
      action = ""
      case report_result
      when "revoked"
        action = "revoking"
      else
        return ""
      end
      "#{secret_type_provider} responded by #{action} the #{reported_token_label}."
    end

    def link_to_bypass_request
      repository = entry.hit[:repository]
      repo_id = entry.hit[:repository_id]
      number = entry.hit[:number]
      request = Exemptions::ExemptionRequest.find_by(request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE, repository: repo_id, number:)
      unless request
        return ""
      end
      helpers.link_to("#{repository}:request##{number}", SecretScanning::BypassDelegation.secret_scanning_bypass_url(T.must(request)))
    end

    def link_to_closure_request_alert
      owner = entry.hit[:org]
      if owner.nil?
        owner = entry.hit[:emu_owner]
      end
      repo = entry.hit[:repo]
      alert_number = entry.hit[:alert_number]
      repo_name = repo.split("/")[1]
      return "" if repo_name.nil? || owner.nil?

      helpers.link_to("#{repo}:alert##{alert_number}", urls.repository_react_alerts_show_path(owner, repo_name, alert_number))
    end

    def link_to_alert
      owner = entry.hit[:org]
      if owner.nil?
        owner = entry.hit[:emu_owner]
      end
      repo = entry.hit[:repo]
      number = entry.hit[:number]
      repo_name = repo.split("/")[1]
      return "" if repo_name.nil? || owner.nil?

      helpers.link_to("#{repo}:alert##{number}", urls.repository_react_alerts_show_path(owner, repo_name, number))
    end

    def deleted_alert_details
      repo = entry.hit[:repo]
      number = entry.hit[:number]
      reason = entry.hit[:reason]

      "GitHub deleted alert number ##{number} in #{repo} because #{reason}"
    end

    def link_to_dependabot_alert
      repo = entry.hit[:repo]
      alert = RepositoryVulnerabilityAlert.find_by(id: entry.hit[:alert_id])

      if alert
        helpers.link_to("#{repo}:alert##{alert.number}", alert.permalink(include_host: false))
      else
        link_to_repo
      end
    end

    def dependabot_alert_dismiss_reason
      entry.hit[:dismiss_reason]&.downcase
    end

    def dependabot_alert_rule_name
      entry.hit[:vulnerability_alert_rule_name]
    end

    def link_to_dependabot_alert_rule_context
      if entry.hit[:repo]
        link_to_repo
      elsif entry.hit[:org]
        link_to_org
      end
    end

    def link_to_repo_custom_pattern
      repo = entry.hit[:repo]
      org = entry.hit[:org]
      id = entry.hit[:custom_pattern][:id]
      name = entry.hit[:custom_pattern][:name]
      repo_name = repo.split("/")[1]
      return "" if repo_name.nil?

      helpers.link_to("#{name}", urls.show_custom_pattern_path(repository: repo.split("/")[1], id: id, user_id: org))
    end

    def custom_pattern_repo
      entry.hit[:repo]
    end

    def link_to_org_custom_pattern
      org = entry.hit[:org]
      id = entry.hit[:custom_pattern][:id]
      name = entry.hit[:custom_pattern][:name]
      helpers.link_to("#{name}", urls.settings_org_security_analysis_show_custom_pattern_path(organization_id: org, id: id))
    end

    def custom_pattern_org
      entry.hit[:org]
    end

    def link_to_business_custom_pattern
      business = entry.hit[:business]
      id = entry.hit[:custom_pattern][:id]
      name = entry.hit[:custom_pattern][:name]
      helpers.link_to("#{name}", urls.settings_business_show_custom_pattern_enterprise_path(slug: business, id: id))
    end

    def custom_pattern_name
      entry.hit[:custom_pattern][:name]
    end

    def push_protection_bypass_reason
      reason = entry.hit[:push_protection_bypass_reason]

      case reason&.upcase
      when "FALSE_POSITIVE" then "false positive"
      when "USED_IN_TESTS" then "used in tests"
      when "WILL_FIX_LATER" then "will fix later"
      else "unknown"
      end
    end

    def link_to_hook
      if entry.hit.data[:hook_type] == "repo" && entry.hit.data[:hook_id].present?
        link_to_repo_hook
      elsif entry.hit.data[:hook_type] == "org" && entry.hit.data[:hook_id].present?
        link_to_org_hook
      elsif entry.hit.data[:hook_type] == "business" && entry.hit.data[:hook_id].present?
        link_to_business_hook
      elsif entry.hit.data[:hook_type] == "sponsors_listing" && entry.hit.data[:hook_id].present?
        link_to_sponsors_listing_hook
      elsif entry.hit.data[:hook_type] == "global" && entry.hit.data[:hook_id].present? && GitHub.single_business_environment?
        # special handling for pre-existing global hook audit log entries
        link_to_business_hook(GitHub.global_business.slug)
      else
        safe_hook_name
      end
    end

    def safe_hook_name
      if entry.hook_name
        entry.hook_name
      else
        "webhook"
      end
    end

    def link_or_show_license_id
      if entry.hit[:business]
        helpers.link_to(entry.hit.data[:license_id], urls.settings_billing_enterprise_path(entry.hit[:business]))
      else
        entry.hit.data[:license_id]
      end
    end

    def link_to_org_label
      return unless org = entry.hit[:org]

      label_name = entry.hit.data[:organization_default_label].to_s
      helpers.link_to(label_name, "/organizations/#{org}/settings/labels")
    end

    ENVIRONMENT_PROTECTION_RULE_HASH = {
      "timeout" => "wait",
      "manual_approval" => "required reviewers",
      "branch_policy" => "deployment branch",
      "branch_policy_pattern" => "deployment branch pattern",
      "tag_policy_pattern" => "deployment tag pattern",
    }.freeze

    def friendly_protection_rule_name
      ENVIRONMENT_PROTECTION_RULE_HASH.fetch(entry.hit.data[:gate_type], entry.hit.data[:gate_type])
    end

    def link_to_environment
      env_name = entry.hit.data[:environment_name] || entry.hit.data.dig(:environment, :environment, :name) || entry.hit.data[:env_name] || entry.hit.data[:name]
      path = environment_path
      if env_name.nil?
        "(missing environment)"
      elsif path.nil?
        env_name
      else
        helpers.link_to(env_name, environment_path)
      end
    end

    def link_to_environment_secrets
      path = environment_path
      if path.nil?
        entry.hit.data[:key]
      else
        helpers.link_to(entry.hit.data[:key], environment_path)
      end
    end

    def link_to_approvers_was
      link_to_approvers_list(entry.hit.data[:approvers_was])
    end

    def link_to_approvers
      link_to_approvers_list(entry.hit.data[:approvers])
    end

    def link_to_approvers_list(approvers)
      return if approvers.nil?

      links = approvers.map do |approver|
        if approver.nil?
          link_to_user(User.ghost)
        elsif approver.key?(:user)
          link_to_user(approver[:user])
        else
          team_name = approver[:team].split("/").last
          helpers.link_to(team_name, "/orgs/#{entry.hit[:org]}/teams/#{team_name}")
        end
      end

      helpers.safe_join(links, ", ")
    end

    def link_to_workflow_run
      workflow_run_id = entry.hit[:workflow_run_id]
      repo_id = entry.hit[:repo_id]

      workflow_run = Actions::WorkflowRun.find_by(id: workflow_run_id, repository_id: repo_id)
      label_name = entry.hit[:run_number] ? "##{entry.hit[:run_number]}" : "id:#{workflow_run_id}"
      if workflow_run
        helpers.link_to(label_name, "/#{entry.hit[:repo]}/actions/runs/#{workflow_run_id}")
      else
        # workflow_run is deleted
        helpers.link_to(label_name, "/#{entry.hit[:repo]}/actions?query=#{CGI::escape("workflow:\"#{entry.hit[:name]}\"")}")
      end
    end

    def link_to_workflow_check_run
      check_run_id = entry.hit[:check_run_id]
      repo_id = entry.hit[:repo_id]
      check_run_exists = Checks.domain.check_runs.for_id(check_run_id, repository_id: repo_id).present?
      if check_run_exists
        helpers.link_to("##{check_run_id}", "/#{entry.hit[:repo]}/runs/#{check_run_id}?check_suite_focus=true")
      end
    end

    def environment_path
      env_id = entry.hit.data[:environment_id] || entry.hit.data.dig(:environment, :environment, :id) || entry.hit.data[:env_id]
      urls.edit_repository_environment_path(*entry.hit[:repo].split("/"), environment_id: env_id) if env_id.present?
    end

    def renamed_repo
      if entry.hit[:org].present?
        "#{entry.hit[:org]}/#{entry.hit.data[:old_name]}"
      elsif entry.hit[:user].present?
        "#{entry.hit[:user]}/#{entry.hit.data[:old_name]}"
      else
        entry.hit[:repo]
      end
    end

    def transferred_repo
      if entry.hit.data[:repo_was].present?
        entry.hit.data[:repo_was]
      elsif entry.hit[:org].present? && entry.hit.data[:old_user].present?
        entry.hit[:repo].sub("#{entry.hit[:org]}/", "#{entry.hit.data[:old_user]}/")
      else
        entry.hit[:repo]
      end
    end

    def topic
      entry.hit.data[:topic]
    end

    def email
      entry.hit.data[:email]
    end

    def old_email
      entry.hit.data[:old_email]
    end

    def old_email?
      old_email.present?
    end

    # Different models use different keys for auditing the responsible
    # OAuth application.
    def oauth_application_id
      entry.hit.data[:application_id] || entry.hit.data[:oauth_application_id]
    end

    def oauth_application_name
      entry.hit.data[:application_name]
    end

    def oauth_application?
      oauth_application_id && oauth_application_id != OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
    end

    def oauth_access_type
      case entry.hit.data[:application_type]
      when "Integration"
        "GitHub App"
      when "OauthApplication"
        if personal_access_token?
          "Personal access token (Classic)"
        else
          "OAuth app"
        end
      end
    end

    def personal_access_token?
      oauth_application_id && oauth_application_id == OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
    end

    def oauth_type
      if oauth_application?
        "OAuth application"
      elsif personal_access_token?
        "personal access token"
      end
    end

    def oauth_scopes
      entry.hit.data[:scopes] && entry.hit.data[:scopes].join(", ")
    end

    def pat_field_changed
      entry.hit.data[:pat_field_changed]
    end

    def hook_active?
      entry.hit.data[:active]
    end

    def hook_active_was?
      entry.hit.data[:active_was]
    end

    def hook_events
      entry.hit.data[:events] && entry.hit.data[:events].join(", ")
    end

    def hook_events_were
      entry.hit.data[:events_were] && entry.hit.data[:events_were].join(", ")
    end

    def plan_duration_change?
      entry.hit.data[:old_plan_duration] != entry.hit.data[:plan_duration]
    end

    def plan_changed?
      entry.hit.data[:old_plan] != entry.hit.data[:plan] &&
        !pricing_model_changed_to_per_seat? && !pricing_model_changed_to_per_repo?
    end

    def business_plan_changed?
      entry.hit.data[:old_plan] != entry.hit.data[:plan]
    end

    def pricing_model_changed_to_per_seat?
      entry.hit.data[:old_plan] != entry.hit.data[:plan] &&
        per_seat_plan?(entry.hit.data[:plan])
    end

    def pricing_model_changed_to_per_repo?
      entry.hit.data[:old_plan] != entry.hit.data[:plan] &&
        per_seat_plan?(entry.hit.data[:old_plan])
    end

    def seat_count_changed?
      per_seat_plan?(entry.hit.data[:plan]) && entry.hit.data[:old_seats].to_i != seats
    end

    def per_seat_plan?(plan_name)
      GitHub::Plan.find(plan_name).try(:per_seat?)
    end

    def seat_delta
      seats - entry.hit.data[:old_seats].to_i
    end

    def seat_purchase?
      seats >= entry.hit.data[:old_seats].to_i
    end

    def email_invitation?
      entry.hit[:user].blank? && entry.hit.data[:email].present?
    end

    def invitation_role
      case entry.hit.data[:role]
      when "direct_member"
        "as member"
      when "admin"
        "as admin"
      when "billing_manager"
        "as billing manager"
      when "reinstate"
        "reinstating the previous role"
      else
        ""
      end
    end

    def link_to_issue
      if issue = entry.issue
        helpers.link_to("#{issue.repository.name_with_display_owner}##{issue.number}", "/#{issue.repository.name_with_display_owner}/issues/#{issue.number}")
      end
    end

    def link_to_new_issue
      if issue = entry.issue_transfer&.new_issue
        helpers.link_to("#{issue.repository.name_with_display_owner}##{issue.number}", "/#{issue.repository.name_with_display_owner}/issues/#{issue.number}")
      end
    end

    def link_to_issue_comment_author
      if issue_comment = entry.issue_comment
        helpers.link_to(issue_comment.user, "/#{issue_comment.user}")
      end
    end

    def link_to_issue_comment
      if issue_comment = entry.issue_comment
        anchor = comment_dom_id(issue_comment)
        helpers.link_to("issue comment", urls.issue_path(issue_comment.issue, anchor: anchor))
      end
    end

    def link_to_commit_comment_author
      if commit_comment = entry.commit_comment
        helpers.link_to(commit_comment.user, "/#{commit_comment.user}")
      end
    end

    def link_to_commit_comment
      if commit_comment = entry.commit_comment
        helpers.link_to("commit comment", commit_comment.full_permalink(include_host: false))
      end
    end

    def link_to_discussion
      if (discussion = entry.discussion) && discussion.repository
        helpers.link_to("discussion", "/#{discussion.repository.name_with_display_owner}/discussions/#{discussion.number}")
      end
    end

    def link_to_discussion_author
      if discussion = entry.discussion
        helpers.link_to(discussion.author, "/#{discussion.author}")
      end
    end

    def link_to_discussion_comment
      if discussion_comment = entry.discussion_comment
        helpers.link_to(
          "discussion comment",
          urls.discussion_comment_show_path_from(discussion: discussion_comment.discussion, comment_id: discussion_comment.id),
        )
      end
    end

    def link_to_discussion_comment_author
      if discussion_comment = entry.discussion_comment
        helpers.link_to(discussion_comment.author, "/#{discussion_comment.author}")
      end
    end

    def link_to_minimizable_author
      if minimizable = entry.minimizable
        helpers.link_to(minimizable.user, "/#{minimizable.user}")
      end
    end

    def link_to_minimizable
      if minimizable = entry.minimizable
        anchor = comment_dom_id(minimizable)
        case minimizable.class.to_s
        when "CommitComment"
          helpers.link_to(
            "commit comment",
            urls.commit_path(minimizable.commit_id, minimizable.repository) + "##{anchor}",
          )
        when "GistComment"
          gist = minimizable.gist
          helpers.link_to("gist comment", urls.user_gist_path(gist.user_param, gist, anchor: anchor))
        when "IssueComment"
          helpers.link_to("issue comment", urls.issue_path(minimizable.issue, anchor: anchor))
        when "PullRequestReview"
          helpers.link_to(
            "pull request review",
            urls.pull_request_path(minimizable.pull_request) + "##{anchor}",
          )
        when "PullRequestReviewComment"
          helpers.link_to(
            "pull request review comment",
            urls.pull_request_path(minimizable.pull_request) + "##{anchor}",
          )
        when "PullRequestReviewThread"
          helpers.link_to(
            "pull request review comment thread",
            urls.pull_request_path(minimizable.pull_request) + "##{anchor}",
          )
        end
      end
    end

    def admin_enforced?
      entry.hit.data[:admin_enforced]
    end

    def dismiss_stale_reviews_on_push?
      entry.hit.data[:dismiss_stale_reviews_on_push]
    end

    def require_code_owner_review?
      entry.hit.data[:require_code_owner_review]
    end

    def require_last_push_approval?
      entry.hit.data[:require_last_push_approval]
    end

    def ignore_approvals_from_contributors?
      entry.hit.data[:ignore_approvals_from_contributors]
    end

    def required_status_checks_enforcement_level
      return if entry.hit.data[:required_status_checks_enforcement_level].blank?

      integer_value = entry.hit.data[:required_status_checks_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def pull_request_reviews_enforcement_level
      return if entry.hit.data[:pull_request_reviews_enforcement_level].blank?

      integer_value = entry.hit.data[:pull_request_reviews_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def signature_requirement_enforcement_level
      return if entry.hit.data[:signature_requirement_enforcement_level].blank?

      integer_value = entry.hit.data[:signature_requirement_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def linear_history_requirement_enforcement_level
      return if entry.hit.data[:linear_history_requirement_enforcement_level].blank?

      integer_value = entry.hit.data[:linear_history_requirement_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def required_review_thread_resolution_enforcement_level
      return if entry.hit.data[:required_review_thread_resolution_enforcement_level].blank?

      integer_value = entry.hit.data[:required_review_thread_resolution_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def allow_force_pushes_enforcement_level
      return if entry.hit.data[:allow_force_pushes_enforcement_level].blank?

      integer_value = entry.hit.data[:allow_force_pushes_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def allow_deletions_enforcement_level
      return if entry.hit.data[:allow_deletions_enforcement_level].blank?

      integer_value = entry.hit.data[:allow_deletions_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def lock_branch_enforcement_level
      return if entry.hit.data[:lock_branch_enforcement_level].blank?

      integer_value = entry.hit.data[:lock_branch_enforcement_level]
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def merge_queue_enforcement_level
      data_hash = entry&.hit&.data
      return if data_hash.blank?

      integer_value = data_hash[:merge_queue_enforcement_level]
      return if integer_value.blank?
      ProtectedBranch::LEVELS.invert[integer_value]
    end

    def changed_merge_queue_settings
      data_hash = entry&.hit&.data
      return if data_hash.blank?

      MergeQueue::NEW_ENGINE_SETTINGS.each_with_object({}) do |key, hash|
        if (value = data_hash[key]).present?
          hash[key] = value
        end
      end
    end

    def lock_allows_fetch_and_merge?
      entry.hit.data[:lock_allows_fetch_and_merge]
    end

    def link_to_actor_avatar
      return actor_avatar unless entry.actor?

      safe_actor = entry.safe_actor
      display_login = safe_actor.respond_to?(:display_login) ? safe_actor.display_login : safe_actor
      helpers.link_to(
        actor_avatar,
        urls.user_path(safe_actor),
        :class => "member-list-avatar tooltipped tooltipped-s",
        "aria-label" => "View #{display_login}'s profile",
      )
    end

    def actor_avatar
      avatar_for(entry.safe_actor, 25, class: :avatar)
    end

    def child_avatar
      return unless display_user_avatar?
      avatar_for(entry.safe_user, 14, class: "avatar avatar-child")
    end

    def link_to_org_person_sso(login: entry.safe_actor_login)
      return link_to_user(User.ghost) if entry.actor_deleted?
      return link_to_actor if entry.org.nil?

      sso_page_path = if entry.org.business&.saml_sso_enabled?
        urls.enterprise_person_sso_enterprise_path(entry.org.business, login)
      else
        urls.org_person_sso_path(org: entry.org, person_login: login)
      end

      helpers.link_to login,
        sso_page_path,
        :class => "member-link",
        "data-pjax" => true
    end

    # The following logic is order specific. Any future changes need to keep this in mind.
    # EMU businesses can see IPs for all activity. If not EMU, we need to check the public_repo field. If it's
    # before that field was available, we return 'unknown'. If a public_repo field is found, we filter the IP based
    # on its value. If there is no public_repo field, we defer to the ip-safe-actions allowlist.
    def org_business_actor_ip
      if entry.is_emu?
        return actor_ip
      end
      if entry.before_public_repo_cutoff?
        return "Unknown IP address"
      end
      unless entry.public_repo.nil?
        if entry.public_repo?
          return "Public repository"
        else
          return actor_ip
        end
      end
      unless entry.ip_safe_action?
        return "Unknown IP address"
      end

      actor_ip
    end

    def actor_ip
      return "Unknown IP address" if entry.actor_ip.blank?
      return "Internal IP address" if entry.internal_ip?

      helpers.link_to entry.actor_ip,
        view.search_path(ip: entry.actor_ip),
        "data-pjax" => true
    end

    def hashed_token
      return if entry.hashed_token.blank?
      helpers.link_to(entry.hashed_token,
        view.search_path(hashed_token: "\"#{entry.hashed_token}\"").gsub(/%5C%22/, ""),
        "data-pjax" => true)
    end

    def token_id
      return if entry.token_id.blank?
      return entry.token_id if view.search_path == "/settings/security-log"
      helpers.link_to(entry.token_id,
        view.search_path(token_id: "#{entry.token_id}"), "data-pjax" => true)
    end

    def external_identity
      return unless business?
      return if entry.external_identity_username.blank? && entry.external_identity_nameid.blank?
      entry.is_emu? ? entry.external_identity_username : entry.external_identity_nameid
    end

    def show_enterprise_person_sso_path?
      return false unless business?
      return false if entry.actor_deleted?

      this_business.enterprise_managed_user_enabled? || this_business.saml_sso_enabled?
    end

    def token_type
      return unless business?
      authorized_credential_type || entry.token_type&.humanize
    end

    def programmatic_access_type
      entry.programmatic_access_type
    end

    def token_scopes
      return if entry.token_scopes.blank? || !business?
      entry.token_scopes.split(",").to_sentence
    end

    def geolocation
      return "Unknown location" unless entry.location?
      entry.location.values_at(:city, :region_name, :country_name).compact.join(", ")
    end

    def country
      return "Unknown location" unless entry.location?

      helpers.link_to entry.country.to_s,
        view.search_path(country: entry.country_code),
        "data-pjax" => true
    end

    def level
      entry.hit.data[:level]
    end

    def enterprise_installation_link
      helpers.link_to entry.hit.data[:customer_name], "http#{"s" unless entry.hit.data[:http_only]}://#{entry.hit.data[:enterprise_installation]}/"
    end

    def license_user_or_email
      user = entry.hit[:user]

      if user.present?
        helpers.link_to(user, "/#{user}")
      else
        entry.hit[:email]
      end
    end

    def authorized_credential_type
      case entry.hit.data[:credential_type]
      when "OauthAccess"
        if entry.hit.data[:oauth_credential_type].present?
          entry.hit.data[:oauth_credential_type]
        else
          "Personal Access Token"
        end
      when "PublicKey"
        "SSH Key"
      end
    end

    def authorized_credential_fingerprint
      case entry.hit.data[:credential_type]
      when "OauthAccess"
        if entry.hashed_token.present?
          entry.hashed_token
        else
          return "deleted" if authorized_credential.blank?
          "#{ "*" * 5 }#{authorized_credential.token_last_eight}"
        end
      when "PublicKey"
        if entry.hit.data[:fingerprint].present?
          entry.hit.data[:fingerprint]
        else
          return "deleted" if credential_authorization.blank?
          credential_authorization.fingerprint
        end
      end
    end

    def prepaid_refill_amount
      Billing::Money.new(entry.hit.data["amount_in_subunits"], entry.hit.data["currency_code"])
    end

    def this_business
      return unless business?
      return @this_business if defined?(@this_business)
      @this_business = Business.find(entry.business_id)
    end

    # Old Actions policy audit log event

    ACTION_EXECUTION_CAPABILITY_HASH = {
      "all" => "all actions and workflows for all repositories",
      "local_actions" => "local actions and workflows for all repositories",
      Actions::PolicyUpdater::DISABLED => "disabled",
      "all_actions_for_selected" => "all actions and workflows for selected repositories",
      "local_only_for_selected" => "local actions and workflows for selected repositories",
    }.freeze

    def friendly_action_execution_capability_name(permission)
      ACTION_EXECUTION_CAPABILITY_HASH.fetch(permission, permission)
    end

    def from_api?
      entry.data["request_category"] == "api"
    end

    def from_api_string
      " via the API " if from_api?
    end

    def previous_action_execution_capability
      friendly_action_execution_capability_name(entry.hit.data[:old_capability])
    end

    def new_action_execution_capability
      friendly_action_execution_capability_name(entry.hit.data[:new_capability])
    end

    def updated_actions_access_policy?
      entry.hit.data[:updated_access_policy]
    end

    def updated_allowed_actions_types?
      entry.hit.data[:updated_allowed_types]
    end

    def updated_actions_allowlist_patterns?
      entry.hit.data[:updated_patterns]
    end

    def updated_actions_allowlist_options?
      entry.hit.data[:updated_github_owned_allowed] || entry.hit.data[:updated_verified_allowed]
    end

    def previous_actions_access_policy
      friendly_actions_access_policy_name(access_policy: entry.hit.data[:old_policy])
    end

    def new_actions_access_policy
      friendly_actions_access_policy_name(access_policy: entry.hit.data[:new_policy])
    end

    ACTIONS_ACCESS_POLICY_HASH = {
      Configurable::ActionsAccess::ALL_ENTITIES => "all entities",
      Configurable::ActionsAccess::SELECTED_ENTITIES => "selected entities",
      Configurable::ActionsAccess::NO_ENTITIES => "no entities",
    }.freeze

    def friendly_actions_access_policy_name(access_policy:)
      ACTIONS_ACCESS_POLICY_HASH.fetch(access_policy, access_policy)
    end

    ALLOWED_ACTIONS_TYPE_HASH = {
      Actions::AllowedTypesUpdater::ALL => "all actions and workflows",
      Actions::AllowedTypesUpdater::SELECTED => "selected actions and workflows",
      Actions::AllowedTypesUpdater::LOCAL_ONLY => "local actions and workflows",
    }.freeze

    def friendly_allowed_actions_type_name(allowed_actions_policy:)
      ALLOWED_ACTIONS_TYPE_HASH.fetch(allowed_actions_policy, allowed_actions_policy)
    end

    def new_allowed_actions
      friendly_allowed_actions_type_name(allowed_actions_policy: entry.hit.data[:new_policy])
    end

    def actions_allowlist_option_changes
      changes = []
      unless entry.hit.data[:updated_github_owned_allowed].nil?
        change = entry.hit.data[:updated_github_owned_allowed] ? "allow" : "disallow"
        changes << "#{change} actions created by GitHub"
      end

      unless entry.hit.data[:updated_verified_allowed].nil?
        change = entry.hit.data[:updated_verified_allowed] ? "allow" : "disallow"
        changes << "#{change} verified actions"
      end

      changes.to_sentence
    end

    def policy_text
      "actions and workflows"
    end

    ACTIONS_FORK_PR_APPROVALS_POLICY_HASH = {
      Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTORS => "first-time contributors",
      Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTOR_NEW_USERS => "first-time contributors new to GitHub",
      Configurable::ActionsForkPrApprovals::ALL_OUTSIDE_COLLABORATORS => "all outside collaborators",
    }.freeze

    def friendly_actions_fork_pr_approvals_policy_name
      policy = entry.hit.data["policy"]
      ACTIONS_FORK_PR_APPROVALS_POLICY_HASH.fetch(policy, policy)
    end

    IMMUTABLE_RELEASES_POLICY_HASH = {
      Releases::ImmutableOrganizationConfig::ALL => "all repositories",
      Releases::ImmutableOrganizationConfig::SELECTED => "selected repositories",
      Releases::ImmutableOrganizationConfig::NONE => "no repositories",
    }.freeze

    def previous_immutable_releases_policy
      policy = entry.hit.data[:old_policy] || "none"
      IMMUTABLE_RELEASES_POLICY_HASH.fetch(policy, policy)
    end

    def new_immutable_releases_policy
      policy = entry.hit.data[:new_policy]
      IMMUTABLE_RELEASES_POLICY_HASH.fetch(policy, policy)
    end

    def link_to_org_secrets
      secret_name = entry.hit.data[:key]
      helpers.link_to(secret_name, urls.settings_org_secrets_path(entry.hit[:org], app_name: secrets_app_name))
    end

    def link_to_org_variables
      variable_name = entry.hit.data[:key]
      helpers.link_to(variable_name, urls.organization_variables_path(entry.hit[:org], app_name: "actions"))
    end

    def link_to_repo_variables
      variable_name = entry.hit.data[:key]
      helpers.link_to(variable_name, "/#{entry.hit[:repo]}/settings/variables/actions")
    end

    def secrets_app_name
      Apps::Privileged.property(:audit_log_secrets_app_name, app: integration) || "actions"
    end

    def actions_share_old_policy
      friendly_actions_share_policy(entry.hit.data[:old_policy])
    end

    def actions_share_policy
      friendly_actions_share_policy(entry.hit.data[:policy])
    end

    def friendly_actions_share_policy(policy)
      policy_value = policy || Configurable::ActionsRepositorySharePolicy::NONE

      # `org_name` field changed to `owner_name` as the policy is now available to user-owned repos as well
      # below logic handles both old and new audit log entries
      owner = entry.hit.data[:owner_name] || entry.hit.data[:org_name]

      # old entries are only related to internal repos, therefore setting `is_owner_org` and `is_repo_internal` to true if entry is not present
      is_owner_org = entry.hit[:is_owner_organization].nil? ? true : entry.hit.data[:is_owner_organization]
      is_repo_internal = entry.hit[:is_repo_internal].nil? ? true : entry.hit.data[:is_repo_internal]

      policy_item = Actions::Policy::RepositoryShareComponent.options(owner, entry.hit.data[:business_name], is_owner_org, is_repo_internal).find { |item| item[:value] == policy_value }
      policy_item[:text] unless policy_item.nil?
    end

    def previous_custom_images_policy
      entry.hit.data[:old_policy]
    end

    def new_custom_images_policy
      entry.hit.data[:new_policy]
    end

    def custom_role_name
      entry.hit.data[:name]
    end

    def custom_role_changed?
      entry.hit.data.has_key?(:changes)
    end

    def previous_custom_role_name
      entry.hit.data.dig(:changes, :old_name)
    end

    def custom_role_base_role
      entry.hit.data[:base_role]
    end

    def previous_custom_role_base_role
      entry.hit.data.dig(:changes, :old_base_role)
    end

    def custom_role_permissions
      entry.hit.data[:role_permissions]
    end

    def previous_custom_role_permissions
      entry.hit.data.dig(:changes, :old_role_permissions)
    end

    def interaction_limit_duration_phrase
      if entry.hit["duration"].present?
        duration_text = ::RepositoryInteractionAbility::DURATION_AUDIT_LOG_MAPPING[entry.hit["duration"]]
        "for #{duration_text.to_s.humanize.downcase}"
      end
    end

    def org_name
      entry.hit[:org]
    end

    def package
      entry.hit.data[:package]
    end

    def ecosystem

      return unless entry.hit.data[:ecosystem]

      ecosystems = {
        "container" => "Container",
        "docker" => "Docker",
        "npm" => "npm",
        "maven" => "Maven",
        "nuget" => "NuGet",
        "rubygems" => "RubyGems"
      }

      ecosystems[entry.hit.data[:ecosystem].to_s.downcase]
    end

    def version_count
      entry.hit.data[:version_count]
    end

    def storage_bytes(human_readable: false)
      human_readable ? ActiveSupport::NumberHelper.number_to_human_size(entry.hit.data[:storage_bytes]) : entry.hit.data[:storage_bytes]
    end

    def version
      entry.hit.data[:version]
    end

    def republished?
      entry.hit.data[:is_republished]
    end

    ALLOWED_ADV_SECURITY_UPDATE_TYPE_HASH = {
      Configurable::AdvancedSecurityAccessPolicy::ALL_ENTITIES => "allow access for all child entities",
      Configurable::AdvancedSecurityAccessPolicy::SELECTED_ENTITIES => "allow access for selected child entities",
      Configurable::AdvancedSecurityAccessPolicy::NO_ENTITIES => "deny access for all child entities",
    }.freeze

    def advanced_security_update_new_policy_pretty
      new_policy = entry.hit.data[:new_policy]
      ALLOWED_ADV_SECURITY_UPDATE_TYPE_HASH.fetch(new_policy, new_policy)
    end

    def security_product_enablement_new_policy
      entry.hit.data[:new_policy]
    end

    def sponsorship_monthly_amount_in_cents
      entry.hit.data[:current_tier_monthly_amount_in_cents]
    end

    def one_time_sponsorship?
      frequency = entry.hit.data[:frequency]
      frequency && frequency.to_sym == :one_time
    end

    def sponsors_agreement_name
      return @sponsors_agreement_name if defined?(@sponsors_agreement_name)
      @sponsors_agreement_name = entry.hit.data[:sponsors_agreement]
    end

    def sponsors_agreement_version
      return unless sponsors_agreement_name.present?
      entry.hit.data[:version]
    end

    def sponsors_tier_name
      return @sponsors_tier_name if defined?(@sponsors_tier_name)
      @sponsors_tier_name = entry.hit.data[:sponsors_tier]
    end

    def link_to_old_repo
      return link_to_old_repo_from_id unless entry.hit[:old_repo]
      helpers.link_to(entry.hit[:old_repo], "/#{entry.hit[:old_repo]}")
    end

    def link_to_old_repo_from_id
      repo_id = entry.hit[:old_repo_id]

      repo = if repo_id
        if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          Repositories.domain.by_id(repo_id)
        else
          Repository.find_by(id: repo_id)
        end
      end
      if repo
        helpers.link_to(repo.name_with_display_owner, "/#{repo.name_with_display_owner}")
      else
        "[unknown repo]"
      end
    end

    def link_to_org_codespaces_policy
      if org?
        helpers.link_to("policy", settings_org_codespaces_policies_path(entry.hit[:org]))
      end
    end

    def link_to_business_codespaces_policy
      if business?
        helpers.link_to("policy", settings_codespaces_policies_enterprise_path(entry.hit[:business]))
      end
    end

    def old_default_branch
      entry.hit[:old_default_branch] || entry.hit.data.dig(:changes, :old_default_branch) || "[unknown branch]"
    end

    def default_branch
      entry.hit[:default_branch] || entry.hit.data.dig(:changes, :default_branch) || "[unknown branch]"
    end

    def entity_name
      entry.org? ? "organization" : "enterprise"
    end

    def safe_entity_name
      entry.org? ? entry.safe_organization_name : entry.safe_business_name
    end

    def link_to_inviter
      link_to_user(entry.hit.data[:inviter])
    end

    def link_to_invitee
      link_to_user(entry.hit.data[:invitee])
    end

    def link_to_ruleset_source
      case entry.hit.data[:ruleset_source_type]
      when "Enterprise"
        link_to_business
      when "Organization"
        link_to_org
      when "Repository"
        link_to_repo
      else
        "[unknown source]"
      end
    end

    COPILOT_ORG_ENABLEMENT_SETTING_HASH = {
      "all_organizations" => "enabled for all organizations",
      "selected_organizations" => "enabled for selected organizations"
    }

    COPILOT_SEAT_MANAGEMENT_SETTING_HASH = {
      "enabled_for_all" => "enabled for all teams and users",
      "enabled_for_selected" => "enabled for selected teams and users"
    }

    def friendly_copilot_enablement_policy(policy)
      COPILOT_ORG_ENABLEMENT_SETTING_HASH.fetch(policy, policy)
    end

    def previous_copilot_enablement_policy
      friendly_copilot_enablement_policy(entry.hit.data[:previous_value])
    end

    def current_copilot_enablement_policy
      friendly_copilot_enablement_policy(entry.hit.data[:current_value])
    end

    def friendly_copilot_seat_management_setting(policy)
      COPILOT_SEAT_MANAGEMENT_SETTING_HASH.fetch(policy, policy)
    end

    def previous_copilot_seat_management_setting
      if entry.hit.data[:previous_value].present?
        friendly_copilot_seat_management_setting(entry.hit.data[:previous_value])
      else
        # for backwards compatibility
        friendly_copilot_seat_management_setting(entry.hit.data[:old_value])
      end
    end

    def current_copilot_seat_management_setting
      friendly_copilot_seat_management_setting(entry.hit.data[:new_value])
    end

    COPILOT_SETTING_NAMES = Copilot::Policies::INSTRUMENTABLE.each_with_object({}) do |policy, hash|
      audit_log_key = policy.instrumentation_key.to_s.delete_suffix("_setting")
      hash[audit_log_key] = "#{policy.display_name} setting"
    end


    COPILOT_SETTING_NAME_OVERRIDES = {
      "editor_chat" => "Copilot Chat setting",
      "copilot" => "Copilot access",
      "public_code_suggestions" => "Copilot public code suggestions setting",
      "editor_chat_setting" => "Copilot Chat setting", # for backwards compatibility
      "copilot_enabled_setting" => "Copilot access",
      "snippy_setting" => "Copilot public code suggestions setting",
      "telemetry_configuration" => "Telemetry configuration",
      "cli" => "Copilot in the CLI setting",
      "desktop" => "Copilot in GitHub Desktop setting",
      "custom_models" => "Copilot fine-tuning setting",
      "private_docs" => "Copilot documentation search setting",
      "usage_telemetry_api" => "Copilot usage metrics setting",
      # adjust these if they are pulled out of the enterprise settings group or if any of the above are added to it
      "github_chat" => "Copilot Enterprise setting",
      "pr_summarizations" => "Copilot Enterprise setting",
      "github_chat_bing_access" => "Bing access for Copilot in GitHub.com setting",
      "copilot_beta_features_opt_in" => "Access to Preview Copilot features in github.com settings",
      "copilot_extensions" => "Copilot extensions setting",
      # unreleased
      "mobile_chat" => "Copilot Chat in GitHub Mobile setting",
      "workspace_for_emu" => "Copilot Workspace setting",
      "insights_setting" => "Copilot Insights setting",
      "ea_user_fallback_policy" => "Copilot policies for enterprise-assigned users setting",
    }

    def friendly_copilot_policy_setting_name(setting_name)
      # first, try the override hash and fallback to the generated hash.
      # if neither of those, just use the setting name
      COPILOT_SETTING_NAME_OVERRIDES.fetch(setting_name, COPILOT_SETTING_NAMES.fetch(setting_name, setting_name))
    end

    SNIPPY_SETTING_HASH = {
      "snippy_enabled" => "blocked",
      "snippy_disabled" => "allowed"
    }

    def friendly_policy_setting_value(setting)
      setting = setting.downcase
      new_value = if setting.include?("unconfigured")
        "unconfigured"
      elsif setting.include?("no_policy")
        "no policy"
      elsif setting.include?("snippy")
        SNIPPY_SETTING_HASH[setting]
      elsif setting.include?("enabled")
        "enabled"
      elsif setting.include?("disabled")
        "disabled"
      else
        setting
      end

      new_value
    end

    def copilot_policy_settings_change
      return "Copilot policy setting changed" unless entry.hit.data[:old_settings].present? && entry.hit.data[:new_settings].present?

      old_settings_hash = entry.hit.data[:old_settings]
      old_settings = old_settings_hash.to_a
      new_settings = entry.hit.data[:new_settings].to_a

      setting_name = T.let("", T.untyped)
      old_value = T.let("", T.untyped)
      new_value = T.let("", T.untyped)
      diff = new_settings - old_settings

      diff.each do |change|
        setting = change[0]
        new_value = friendly_policy_setting_value(change[1])
        setting_name = friendly_copilot_policy_setting_name(setting)
        old_value = friendly_policy_setting_value(old_settings_hash[setting])
      end

      "#{setting_name} changed from #{old_value} to #{new_value}"
    end

    def copilot_plan_changed_message
      if entry.hit.data[:old_plan] == "business" && entry.hit.data[:plan] == "enterprise"
        "The GitHub Copilot plan was upgraded to Copilot Enterprise"
      elsif entry.hit.data[:old_plan] == "enterprise" && entry.hit.data[:plan] == "business"
        "The GitHub Copilot plan was downgraded to Copilot Business"
      else
        "The GitHub Copilot plan is now on Copilot #{entry.hit.data[:plan].capitalize}"
      end
    end

    def copilot_terms_saved_message
      if entry.hit.data[:terms_type] == "pre-release"
        "The GitHub Copilot Pre-Release Preview Terms were agreed to on behalf of"
      else
        "The GitHub Copilot Product Terms were agreed to on behalf of"
      end
    end

    def copilot_seat_assignment_owner_type
      return entry.hit.data[:owner_type] if entry.hit.data[:owner_type].present?
      ""
    end

    def copilot_seat_assignment_details
      return nil unless entry.hit.data[:seat_assignment].present? || entry.hit.data[:assignment].present?
      if entry.hit.data[:seat_assignment].present?
        assignment = entry.hit.data[:seat_assignment]
        { assignee_type: assignment[:assignee_type], assignee: assignment[:assignee] }
      elsif entry.hit.data[:assignment].present?
        # for backwards compatibility
        assignment = entry.hit.data[:assignment]
        { assignee_type: assignment[:assignable_type], assignee: assignment[:assignable] }
      end
    end

    def copilot_seat_cancellation_reason
      return unless entry.hit.data[:job].present?
      if entry.hit.data[:job].include?("OrganizationRemoveMemberJob")
        "they are no longer a member of the organization"
      end
    end

    def copilot_event_type
      return "" unless entry.hit.data[:event_type].present?
      entry.hit.data[:event_type]
    end

    def copilot_seat_unassignment_reason
      case copilot_event_type
      when "team_destroyed_disassociate_seat"
        "the team was destroyed"
      when "team_unassigned_disassociate_seat"
        "the team was unassigned"
      when "unassigned_by_staff"
        "they were unassigned by GitHub staff"
      when "external_identity_deprovisioned"
        "the external identity was deprovisioned"
      when "team_member_removed_disassociate_seat"
        "their team membership changed"
      when "seat_management_disabled"
        "seat management was set to disabled"
      when "seat_management_selected"
        "seat management was set to allow for selected users and teams"
      when "seat_management_allow_all"
        "seat management was set to allow all"
      when "enterprise_teams_migration"
        "business was migrated to enterprise teams"
      else
        nil
      end
    end

    def copilot_seat_addition_reason
      case copilot_event_type
      when "member_added_organization"
        "they were added to the organization, which grants Copilot access for all members"
      when "member_added_team"
        if entry.hit.data[:seat_assignment].present? && entry.hit.data[:seat_assignment][:assignee].present?
          "they were added to team #{entry.hit.data[:seat_assignment][:assignee]} which has an existing Copilot seat"
        else
          "they were added to a team with an existing Copilot seat"
        end
      else
        nil
      end
    end

    def copilot_access_revocation_target
      entry.hit.data[:owner]
    end

    def link_to_copilot_owner
      if org?
        link_to_org(copilot_access_revocation_target)
      elsif business?
        link_to_business(copilot_access_revocation_target)
      end
    end

    def http_request_method
      entry.hit.data[:request_method]
    end

    def alert_numbers
      return entry.hit[:alert_numbers] if entry.hit[:alert_numbers].present?
      return [entry.hit[:alert_number]] if entry.hit[:alert_number].present?
      nil
    end

    def link_to_code_scanning_alert
      repo_id = entry.hit[:repo_id]

      return if repo_id.nil? || alert_numbers.nil?
      repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        Repositories.domain.by_id(repo_id)
      else
        Repository.find_by(id: repo_id)
      end
      if repo
        links = []
        alert_numbers.each do |alert_number|
          alert_url = UrlHelpers.repository_code_scanning_result_path(repo.owner_display_login, repo, number: alert_number)
          links << helpers.link_to("#{repo.name_with_display_owner}##{alert_number}", alert_url)
        end
        safe_join(links, ", ")
      else
        "[unknown alerts]"
      end
    end

    def links_to_code_scanning_alert_assignees
      user_ids = entry.hit[:assigned_user_ids]
      return unless user_ids.present?

      links = User.where(id: user_ids).map { |user| link_to_user(user) }
      safe_join(links, ", ")
    end

    def credential_revoked_via_api?
      entry.data[:explanation] && entry.data[:explanation].downcase&.include?("api")
    end

    private

    def seats
      (entry.hit.data[:seats] || entry.hit.data[:new_seats]).to_i
    end

    def normalized_team_privacy(privacy)
      if privacy == "closed"
        # We eventually plan on introducing an "open" privacy that allows any
        # org member to join the team (whereas "closed" allows any org member to
        # see the team, but they must be added by someone with admin access).
        #
        # Until we introduce "open", the "closed" visibility is misleading, so
        # we say "visible" publicly until then.
        "visible"
      else
        privacy
      end
    end

    def authorized_credential
      return @authorized_credential if defined?(@authorized_credential)
      @authorized_credential =
        case entry.hit[:credential_type]
        when "OauthAccess"
          OauthAccessTokens.domain.by_id(entry.hit.data[:credential_id])
        when "PublicKey"
          PublicKey.find_by(id: entry.hit.data[:credential_id])
        end
    end

    def credential_authorization
      @credential_authorization ||= Organization::CredentialAuthorization.where(
        credential_type: entry.hit.data[:credential_type],
        credential_id: entry.hit.data[:credential_id],
      ).first
    end

    def integration
      return @integration if defined?(@integration)
      @integration = Integration.find_by(id: entry.hit.data[:integration_id])
    end

    def installation
      return @installation if defined?(@installation)
      @installation = nil

      if (installation = IntegrationInstallation.includes(:integration).find_by(id: entry.hit.data[:installation_id]))
        @installation = installation
        integration_id = entry.hit[:integration_id]

        # Save us another lookup if the ids match
        if integration_id.nil? || installation.integration_id == integration_id
          @integration = installation.integration
        end
      end

      @installation
    end

    def sponsor_listing_owner
      if entry.hit[:org].present?
        entry.hit[:org]
      elsif entry.hit[:user].present?
        entry.hit[:user]
      end
    end

    def link_to_sponsors_listing_hook
      helpers.link_to(safe_hook_name, edit_sponsorable_dashboard_webhook_path(sponsor_listing_owner, entry.hit.data[:hook_id]))
    end
  end
end
