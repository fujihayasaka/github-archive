# typed: true
# frozen_string_literal: true

class SecretScanningMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include GitHub::RouteHelpers
  include GitHub::DatadogHelper
  include SecretScanning::Features::FeatureFlagHelper

  self.mailer_name = "mailers/secret_scanning"

  layout "layouts/primer_layout"

  helper :avatar

  TOKEN_SCANNING_SCOPE = T.let({
    commit_scoped: "commit",
    repo_scoped: "repo",
    config_change_scoped: "config_change",
    config_deleted_scoped: "config_deleted",
    reconciliation_scoped: "path_reconciliation",
    custom_pattern_edit_scoped: "custom_pattern_edited",
    custom_pattern_create_scoped: "custom_pattern_created",
    revoke_github_oauth_token_scoped: "revoke_github_oauth_token",
    unverify_github_public_key_scoped: "unverify_github_public_key",
    resolved_alert_reopened_for_active_token_scoped: "resolved_alert_reopened_for_active_token",
    active_alert_resolved_for_revoked_token_scoped: "active_alert_resolved_for_revoked_token",
    bypassed_as_false_positive_scoped: "bypassed_as_false_positive",
    bypassed_as_used_in_tests_scoped: "bypassed_as_used_in_tests",
    bypassed_as_fix_later_scoped: "bypassed_as_fix_later",
    hcs_upgrade_backfill: "hcs_upgrade_backfill",
    lcp_backfill: "lcp_backfill",
    generic_secrets_commit_scoped: "generic_secrets_commit",
    generic_secrets_repo_scoped: "generic_secrets_repo",
  }, T::Hash[Symbol, String])

  ADMIN_ALERTS_LIST_LIMIT = 5
  AUTHOR_ALERTS_LIST_LIMIT = 100
  DATADOG_PREFIX = "commit_author_token_scanning_alert_summary_email.event"

  sig { params(repo: ::Repository, results: T::Array[T::Hash[::Symbol, T.untyped]], users: T::Array[::User], scope: ::String, total_alert_count: T.nilable(::Integer), total_scan_count: T.nilable(::Integer)).returns(T.untyped) }
  def admin_token_scanning_summary(repo, results, users, scope, total_alert_count, total_scan_count)
    ActiveRecord::Base.connected_to(role: :reading) do
      perform_admin_token_scanning_summary(repo, results, users, scope, total_alert_count, total_scan_count)
    end
  end

  # Email for secret authors who are not repository admins
  sig { params(repo: ::Repository, results: T::Array[T::Hash[::Symbol, T.untyped]], email: String, scope: String, total_scan_count: T.nilable(Integer), business: T.nilable(Business)).returns(T.untyped) }
  def secret_author_token_scanning_summary(repo, results, email, scope, total_scan_count, business)
    ActiveRecord::Base.connected_to(role: :reading) do
      perform_secret_author_token_scanning_summary(repo, results, email, scope, total_scan_count, business)
    end
  end

  sig { params(users: T::Array[User], owner: T.any(Business, Organization), job_group_id: Integer, repos_scanned_count: Integer, total_token_count: Integer, security_configuration_name: T.nilable(String)).void }
  def secrets_found_for_initial_org_or_enterprise_backfill(users, owner, job_group_id, repos_scanned_count, total_token_count, security_configuration_name)
    ActiveRecord::Base.connected_to(role: :reading) do
      perform_secrets_found_for_initial_org_or_enterprise_backfill(users, owner, job_group_id, repos_scanned_count, total_token_count, security_configuration_name)
    end
  end

  sig { params(repo: T.any(Repository, Gist), user: User, token_source: Symbol, url: String, key_name: T.nilable(String)).void }
  def ssh_private_key_leaked(repo, user, token_source, url, key_name: nil)
    @repo = repo
    @user = user
    @url = url
    @key_name_text = key_name

    @link_text = link_text_to_leak_source(token_source: token_source)
    @leak_source = leak_source(token_source: token_source)

    subject = "[GitHub] SSH Private Key found in #{@leak_source}"

    headers(leaked_mail_headers(user))
    premail(
      from: github,
      to: user_email(@user, GitHub.newsies.email(@user, @repo.owner).value),
      subject: subject,
    )
  end

  sig { params(repo: T.any(Repository, Gist), user: User, token_source: Symbol, url: String, token_type: T.nilable(String), key_name: T.nilable(String)).void }
  def personal_access_token_leaked(repo, user, token_source, url, token_type:, key_name: nil)
    @repo = repo
    @user = user
    @url = url
    @key_name_text = key_name

    @link_text = link_text_to_leak_source(token_source: token_source)
    @leak_source = leak_source(token_source: token_source)

    subject = "[GitHub] GitHub Personal Access Token found in #{@leak_source}"

    headers(leaked_mail_headers(user))
    premail(
      from: github,
      to: user_email(@user, GitHub.newsies.email(@user, @repo.owner).value),
      subject: subject,
    )
  end

  # This uses lib/hydro/schemas/github/v1/token_scan_pb.rb
  sig { params(token_source: Symbol).returns(String) }
  def leak_source(token_source:)
    case token_source
    when :CONTENT, :COMMIT
      return "commit"
    when :GIST
      return "gist"
    when :PULL_REQUEST_TITLE, :PULL_REQUEST_DESCRIPTION, :PULL_REQUEST_COMMENT
      return "pull request"
    when :ISSUE_TITLE, :ISSUE_DESCRIPTION, :ISSUE_COMMENT
      return "issue"
    when :DISCUSSION_TITLE, :DISCUSSION_BODY, :DISCUSSION_COMMENT
      return "discussion"
    when :COMMIT_COMMENT
      return "commit comment"
    when :WIKI_CONTENT
      return "wiki"
    when :WIKI_COMMIT
      return "wiki commit metadata"
    end
    "repository"
  end

  sig { params(token_source: Symbol).returns(String) }
  def link_text_to_leak_source(token_source:)
    case token_source
    when :CONTENT
      return "the content of a commit"
    when :GIST
      return "the content of gist"
    when :COMMIT
      return "the metadata of a commit"
    when :ISSUE_TITLE
      return "the title of an issue"
    when :ISSUE_DESCRIPTION
      return "the description of an issue"
    when :ISSUE_COMMENT
      return "a comment on an issue"
    when :DISCUSSION_TITLE
      return "the title of a discussion"
    when :DISCUSSION_BODY
      return "the description of a discussion"
    when :DISCUSSION_COMMENT
      return "a comment on a discussion"
    when :PULL_REQUEST_TITLE
      return "the title of a pull request"
    when :PULL_REQUEST_DESCRIPTION
      return "the description of a pull request"
    when :PULL_REQUEST_COMMENT
      return "a comment on a pull request"
    when :COMMIT_COMMENT
      return "a commit comment"
    when :WIKI_CONTENT
      return "the content of a wiki page"
    when :WIKI_COMMIT
      return "the metadata of a commit to this wiki"
    end
    "a repository"
  end

  sig { params(repo: T.any(Repository, Gist), user: User, token_source: Symbol, url: String, token_type: T.nilable(String), app_name: T.nilable(String)).void }
  def github_app_installation_access_token_leaked(
    repo,
    user,
    token_source,
    url,
    token_type:,
    app_name: nil)
    @repo = repo
    @user = user
    @url = url
    @app_name = app_name

    @link_text = link_text_to_leak_source(token_source: token_source)
    @leak_source = leak_source(token_source: token_source)

    subject = "[GitHub] GitHub App Installation Access Token found in #{@leak_source}"

    headers(leaked_mail_headers(user))
    premail(
      from: github,
      to: user_email(@user, GitHub.newsies.email(@user, @repo.owner).value),
      subject: subject,
    )
  end

  sig { params(repo: T.any(Repository, Gist), user: User, token_source: Symbol, url: String, token_type: T.nilable(String), app_name: T.nilable(String)).void }
  def oauth_app_user_access_token_leaked(
    repo,
    user,
    token_source,
    url,
    token_type:,
    app_name: nil)
    @repo = repo
    @user = user
    @url = url
    @app_name = app_name

    @link_text = link_text_to_leak_source(token_source: token_source)
    @leak_source = leak_source(token_source: token_source)

    subject = "[GitHub] OAuth App User Access Token found in #{@leak_source}"

    headers(leaked_mail_headers(user))
    premail(
      from: github,
      to: user_email(@user, GitHub.newsies.email(@user, repo.owner).value),
      subject: subject,
    )
  end

  sig { params(repo: T.any(Repository, Gist), user: User, token_source: Symbol, url: String, token_type: T.nilable(String), app_name: T.nilable(String)).void }
  def github_app_user_access_token_leaked(
    repo,
    user,
    token_source,
    url,
    token_type:,
    app_name: nil)
    @repo = repo
    @user = user
    @url = url
    @app_name = app_name

    @link_text = link_text_to_leak_source(token_source: token_source)
    @leak_source = leak_source(token_source: token_source)

    subject = "[GitHub] GitHub App User Access Token found in #{@leak_source}"

    headers(leaked_mail_headers(user))
    premail(
      from: github,
      to: user_email(@user, GitHub.newsies.email(@user, @repo.owner).value),
      subject: subject,
    )
  end

  sig { params(repo: Repository, user: User, name: String, alert_number: T.nilable(Integer)).void }
  def token_reported(repo, user, name, alert_number)
    @repo = repo
    @user = user
    @token_name = name
    @alert_url = ""
    @is_emu = repo.owner&.is_a?(User) && repo.owner&.enterprise_managed_business.present?

    # The user has access to the alert if the alert number is present
    # otherwise show the org the alert was reported in if the owner is not an EMU
    if alert_number.present?
      @url = @repo.http_url.chomp(".git")
      @url_text = @repo.name_with_display_owner
      @alert_url = "#{GitHub.url}/#{repo.name_with_display_owner}/security/secret-scanning/#{alert_number}"
    end

    subject = "[GitHub] Your GitHub personal access token has been revoked"

    headers(leaked_mail_headers(user))
    premail(
      from: github,
      to: user_email(@user, GitHub.newsies.email(@user, @repo.owner).value),
      subject: subject,
    )
  end

  def custom_pattern_dry_run_scan_summary(owner, owner_scope, custom_pattern, author, results_count)
    ActiveRecord::Base.connected_to(role: :reading) do
      perform_custom_pattern_dry_run_scan_summary(owner, owner_scope, custom_pattern, author, results_count)
    end
  end

  def custom_pattern_dry_run_scan_failed(owner, owner_scope, custom_pattern, author)
    ActiveRecord::Base.connected_to(role: :reading) do
      perform_custom_pattern_dry_run_scan_failed(owner, owner_scope, custom_pattern, author)
    end
  end

  # Notify users of a compromise via a commit containing their username and password
  #
  # user: The compromised user
  def username_and_password_compromised_detected_by_secret_scanning(user:, repo_readable_by_user:, token_source:, url:)
    @user = user
    @url = url if repo_readable_by_user

    leak_source = nil

    case token_source
    when :CONTENT
      @title = "Your username and password were exposed in the content or git logs of a public repository."
      @url_text = "this content"
    when :COMMIT
      @title = "Your username and password were exposed in a commit to a public repository."
      @url_text = "the metadata of this commit"
    when :ISSUE_TITLE, :ISSUE_DESCRIPTION
      @title = "Your username and password were exposed in an issue of a public repository."
      @url_text = "this issue"
    when :ISSUE_COMMENT
      @title = "Your username and password were exposed in an issue of a public repository."
      @url_text = "this issue comment"
    when :DISCUSSION_TITLE, :DISCUSSION_BODY
      @title = "Your username and password were exposed in a discussion of a public repository."
      @url_text = "this discussion"
    when :DISCUSSION_COMMENT
      @title = "Your username and password were exposed in a discussion of a public repository."
      @url_text = "this discussion comment"
    when :PULL_REQUEST_TITLE, :PULL_REQUEST_DESCRIPTION
      @title = "Your username and password were exposed in a pull request of a public repository."
      @url_text = "this pull request"
    when :PULL_REQUEST_COMMENT
      @title = "Your username and password were exposed in a pull request of a public repository."
      @url_text = "this pull request comment"
    when :COMMIT_COMMENT
      @title = "Your username and password were exposed in a commit comment of a public repository."
      @url_text = "this commit comment"
    when :WIKI_CONTENT
      @title = "Your username and password were exposed in a public repository's wiki page."
      @url_text = "this wiki page"
    when :WIKI_COMMIT
      @title = "Your username and password were exposed in a commit to a public repository's wiki."
      @url_text = "the metadata of a commit to this wiki"
    end

    @icon = "token-scanning.png"

    convert_to_premail(mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :username_and_password_compromised_detected_by_secret_scanning,
      subject: "[GitHub] Please change your password",
    ))
  end

  private

  sig { params(user: User, owner: T.any(Repository, Organization, Business)).returns(T::Boolean) }
  def allow_sending_to_email?(user, owner)
    if owner.is_a?(Repository)
      repo_owner = owner.owner
      if repo_owner.is_a?(Organization)
        return repo_owner.user_can_receive_email_notifications?(user)
      end
    elsif owner.is_a?(Organization)
      return owner.user_can_receive_email_notifications?(user)
    else
      # TODO: support email filtering for business scope
      # https://github.com/github/secret-scanning/issues/7639
    end

    true
  end

  def token_display_name(token_type)
    display_name = nil
    if token_type.present?
      case token_type
      when "GITHUB", "GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_TOKEN_V2"
        display_name = "GitHub Personal Access Token"
      when "GITHUB_OAUTH_ACCESS_TOKEN", "GITHUB_USER_TO_SERVER_TOKEN"
        display_name = "OAuth Access Token"
      when "GITHUB_REFRESH_TOKEN"
        display_name = "GitHub Refresh Token"
      when "GITHUB_SERVER_TO_SERVER_TOKEN", "GITHUB_APP_TOKEN"
        display_name = "GitHub App Installation Access Token"
      end
    end
    display_name
  end

  def set_owner_info_from_owner(owner)
    if owner.is_a?(Organization)
      @org_or_enterprise_type = "organization"
      @org_or_enterprise_name = owner.display_login
      if ::SecurityCenter::SecurityFeatures.security_center_available?(owner)
        @alerts_url = security_center_risk_url(owner)
        @alerts_text = "your security overview"
      else
        @alerts_url = settings_org_audit_log_url(owner) + "?q=action%3Asecret_scanning_alert.create++"
        @alerts_text = "the audit log"
      end
    elsif owner.is_a?(Business)
      @org_or_enterprise_type = "enterprise"
      @org_or_enterprise_name = owner.name
      @alerts_url = security_center_alerts_secret_scanning_enterprise_url(owner)
      @alerts_text = "your security overview"
    else
      raise ArgumentError.new("Owner must be an organization or a business")
    end

  end

  def perform_secrets_found_for_initial_org_or_enterprise_backfill(users, owner, job_group_id, repos_scanned_count, total_token_count, security_configuration_name)
    set_owner_info_from_owner(owner)

    if owner.is_a?(Organization)
      users = users.select { |user| allow_sending_to_email?(user, owner) }
    end
    return nil unless users.any?

    @title = "Your historical scan detected #{total_token_count} secrets across #{repos_scanned_count} scanned repositories in your #{@org_or_enterprise_type}"
    @icon = "existing-vulnerability.png"
    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]
    message_id = generate_initial_backfill_message_id(@org_or_enterprise_name, job_group_id)
    email_headers = summary_email_headers(message_id, [])
    headers(email_headers)
    subject = "[#{@org_or_enterprise_name}] Secrets detected in your historical scan"
    @security_config_name = security_configuration_name

    premail(
      from: github,
      to: [],
      bcc: users.map { |user| GitHub.newsies.email(user, owner) },
      subject: subject,
    )
  end

  sig { params(repo: ::Repository, results: T::Array[T::Hash[::Symbol, T.untyped]], users: T::Array[::User], scope: ::String, total_alert_count: T.nilable(::Integer), total_scan_count: T.nilable(::Integer)).returns(T.untyped) }
  def perform_admin_token_scanning_summary(repo, results, users, scope, total_alert_count = nil, total_scan_count = nil)
    if repo.owner.is_a?(Organization)
      owner_org = T.cast(T.must(repo.owner), Organization)
      users = users.select { |user| allow_sending_to_email?(user, owner_org) }
    end
    recipients = build_admin_recipients_list(repo.owner, users)
    return nil unless recipients[:to].any? || recipients[:bcc].any?

    @repo = repo
    @scope = scope
    @title = "Please resolve these alerts"
    @icon = "existing-vulnerability.png"
    @message = "Anyone with read access can view exposed secrets. Consider rotating and revoking each valid secret to avoid any irreversible damage."
    @total_alert_count = total_alert_count if total_alert_count.present?
    @total_scan_count = total_scan_count if total_scan_count.present?
    @alerts_list_limit = ADMIN_ALERTS_LIST_LIMIT
    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]

    @results_path = results_path
    @alerts = alerts_to_list(results)
    @alerts = @alerts.sort_by { |alert| alert.label }

    subject = "[#{@repo.readonly_name_with_display_owner}] "
    @header_prefix = "Action needed: "
    @footer = "You are receiving this email because GitHub scanned for exposed tokens or private key credentials in your repository."
    @skip_bottom_border = false
    case scope
    when TOKEN_SCANNING_SCOPE[:commit_scoped]
      subject += "Possible valid secrets found in commits"
      @header_prefix += "Secrets detected in recent commits to"
    when TOKEN_SCANNING_SCOPE[:config_change_scoped]
      subject += "Possible secrets found after configuration change"
      @header_prefix += "Changes to the configuration found new secrets in"
    when TOKEN_SCANNING_SCOPE[:config_deleted_scoped]
      subject += "Possible secrets found after configuration deletion"
      @header_prefix += "Changes to the configuration found new secrets in"
    when TOKEN_SCANNING_SCOPE[:reconciliation_scoped]
      subject += "Possible secrets found in additional path locations"
      @header_prefix += "New secrets found in additional path locations in"
    when TOKEN_SCANNING_SCOPE[:custom_pattern_edit_scoped]
      subject += "Possible secrets found after custom pattern change"
      @header_prefix += "Edited custom pattern #{@alerts.first.label} found matches in"
    when TOKEN_SCANNING_SCOPE[:custom_pattern_create_scoped]
      subject += "Possible secrets found due to new custom pattern"
      @header_prefix += "New custom pattern #{@alerts.first.label} found matches in"
    when TOKEN_SCANNING_SCOPE[:revoke_github_oauth_token_scoped]
      subject += "User revoked a detected secret"
      @header_prefix = "Secret revoked: User revoked a GitHub token found in"
      display_name = token_display_name(@alerts.first.type)
      @title = "User revoked a detected #{display_name}"
      @message = "A user in your organization requested for GitHub to revoke a secret found in your repository through an associated alert. The secret has been revoked, and we closed the alert."
      @footer = "You are receiving this email because a token in your repository was found by GitHub and revoked."
      @total_alert_count = nil
      @skip_bottom_border = true
    when TOKEN_SCANNING_SCOPE[:unverify_github_public_key_scoped]
      subject += "User unverified a GitHub public SSH key"
      @header_prefix = "Secret revoked: User has unverified a GitHub public SSH key in"
      @title = "User unverified a detected GitHub public SSH key"
      @message = "A user in your organization requested for GitHub to unverify a SSH public key that corresponds to the private key found in your repository through an associated alert. Unverifying the public key prevents unauthorized access to the impacted user. As a consequence, their SSH access to GitHub may be interrupted."
      @footer = "You are receiving this email because a token in your repository was found by GitHub and unverified."
      @total_alert_count = nil
      @skip_bottom_border = true
    when TOKEN_SCANNING_SCOPE[:resolved_alert_reopened_for_active_token_scoped]
      subject += "Alerts reopened for active secrets"
      @header_prefix += "Alerts reopened for active secrets in"
      @title = "Alerts reopened as we detected active secrets"
      @message = "The following secrets were closed in your repository, but our recent scan detected them as still active."
      @secondary_message = "Committed secrets can be discovered by anyone with read access. Consider rotating and revoking each valid secret to avoid any unauthorized access."
    when TOKEN_SCANNING_SCOPE[:active_alert_resolved_for_revoked_token_scoped]
      subject += "Alerts closed for previously revoked secrets"
      @header_prefix += "Alerts closed for revoked secrets in"
      @title = "Alerts closed for previously revoked GitHub secrets"
      @message = "Our recent scan of your repository found that the following GitHub secrets have already been revoked. We closed the associated alerts. Please review the alerts as needed."
    when TOKEN_SCANNING_SCOPE[:bypassed_as_false_positive_scoped]
      subject += "User bypassed a blocked secret"
      @header_prefix = "Secret protection bypassed: User pushed a blocked secret in"
      @title = "Push protection bypassed as a false positive"
      @message = "Anyone with read access can view exposed secrets. If the secret is in use, consider rotating then revoking the secret to avoid unauthorized access."
      @footer = "You are receiving this email because GitHub blocked a commit with a detected secret, and a user bypassed the protection."
      @total_alert_count = nil
      @skip_bottom_border = true
    when TOKEN_SCANNING_SCOPE[:bypassed_as_used_in_tests_scoped]
      subject += "User bypassed a blocked secret"
      @header_prefix = "Secret protection bypassed: User pushed a blocked secret in"
      @title = "Push protection bypassed as a test case"
      @message = "Anyone with read access can view exposed secrets. If the secret is in use, consider rotating then revoking the secret to avoid unauthorized access."
      @footer = "You are receiving this email because GitHub blocked a commit with a detected secret, and a user bypassed the protection."
      @total_alert_count = nil
      @skip_bottom_border = true
    when TOKEN_SCANNING_SCOPE[:bypassed_as_fix_later_scoped]
      subject += "User bypassed a blocked secret"
      @header_prefix = "Secret protection bypassed: User pushed a blocked secret in"
      @title = "Push protection bypassed as fix later"
      @message = "Anyone with read access can view exposed secrets. If the secret is in use, consider rotating then revoking the secret to avoid unauthorized access."
      @footer = "You are receiving this email because GitHub blocked a commit with a detected secret, and a user bypassed the protection."
      @total_alert_count = nil
      @skip_bottom_border = true
    when TOKEN_SCANNING_SCOPE[:hcs_upgrade_backfill]
      subject += "Possible valid secrets found in commits after historical scan"
      @header_prefix = "Secrets detected in some commits after a historical scan of"
      @message = "Secrets were detected due to a historical scan for newly added pattern types."
      @secondary_message = "Committed secrets can be discovered by anyone with read access. If the secret is in use, consider rotating then revoking the secret to avoid unauthorized access."
    when TOKEN_SCANNING_SCOPE[:lcp_backfill]
      subject += "Possible valid secrets found in repository"
      @header_prefix = "Possibly valid secrets detected in"
      @message = "Anyone with read access can view exposed secrets. Review these secrets for validity, and consider rotating them to avoid any irreversible damage."
      @feedback_link = "https://github.com/orgs/community/discussions/categories/code-security"
    when TOKEN_SCANNING_SCOPE[:generic_secrets_commit_scoped]
      subject += "Possible passwords found in commits"
      @header_prefix = "Passwords detected in recent commits to"
      @message = "Anyone with read access can view exposed passwords. Review these passwords for validity, and consider rotating them to avoid any irreversible damage."
      @detected_by_ai = true
    when TOKEN_SCANNING_SCOPE[:generic_secrets_repo_scoped]
      subject += "Possible passwords found in repository"
      @header_prefix = "Passwords detected after historical scan of"
      @message = "Anyone with read access can view exposed passwords. Review these passwords for validity, and consider rotating them to avoid any irreversible damage."
      @detected_by_ai = true
    else
      subject += "Possible valid secrets found in repository"
      @header_prefix = "Secrets detected in"
    end

    first_result_number = find_first_result(results)
    latest_result_number = find_latest_result(results)
    message_id = generate_summary_message_id(repo, latest_result_number)
    references = generate_summary_references(repo, first_result_number)

    email_headers = summary_email_headers(message_id, references)

    headers(email_headers)

    premail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: subject,
    )
  end

  sig { params(repo: ::Repository, results: T::Array[T::Hash[::Symbol, T.untyped]], email: String, scope: String, total_scan_count: T.nilable(::Integer), business: T.nilable(Business)).returns(T.untyped) }
  def perform_secret_author_token_scanning_summary(repo, results, email, scope, total_scan_count, business)
    @repo = repo
    @user = User.find_by_email(email, business: business)

    return nil unless allow_sending_to_email?(@user, @repo)

    subject = "[#{@repo.readonly_name_with_display_owner}] Possible valid secrets detected"
    @header = "Action needed: Secrets detected in"
    @title = "Please resolve these alerts"
    @icon = "existing-vulnerability.png"
    @message = "Anyone with read access can view exposed secrets. Consider rotating and revoking each valid secret to avoid any irreversible damage."
    @detected_by_ai = false
    if scope == TOKEN_SCANNING_SCOPE[:generic_secrets_commit_scoped]
      subject = "[#{@repo.readonly_name_with_display_owner}] Possible passwords detected"
      @header = "Action needed: Passwords detected in"
      @message = "Anyone with read access can view exposed passwords. Review these passwords for validity, and consider rotating them to avoid any irreversible damage."
      @detected_by_ai = true
    elsif [
      TOKEN_SCANNING_SCOPE[:bypassed_as_false_positive_scoped],
      TOKEN_SCANNING_SCOPE[:bypassed_as_used_in_tests_scoped],
    ].include?(scope)
      subject = "[#{@repo.readonly_name_with_display_owner}] Possible valid secrets bypassed"
      @header = "Secrets bypassed push protection in"
      @title = "Review these alerts"
      @message = "Anyone with read access can view exposed secrets. Confirm that each valid secret is rotated and revoked to avoid any irreversible damage."
    end
    @alerts_list_limit = AUTHOR_ALERTS_LIST_LIMIT
    @total_scan_count = total_scan_count if total_scan_count.present?
    ### secret author alert count telemetry
    if total_scan_count.present? && total_scan_count > AUTHOR_ALERTS_LIST_LIMIT
      datadog_count(alert_count: total_scan_count, user_id: @user.id)
    end

    @alerts = alerts_to_list(results)
    @alerts = @alerts.sort_by { |alert| alert.label }

    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]

    latest_result_number = find_latest_result(results)
    message_id = generate_alert_summary_message_id(repo, latest_result_number)

    email_headers = summary_email_headers(message_id)

    headers(email_headers)

    premail(
      from: github,
      to: user_email(@user, GitHub.newsies.email(@user, repo.owner).value),
      bcc: [],
      subject: subject,
    )
  end

  def perform_custom_pattern_dry_run_scan_summary(owner, owner_scope, custom_pattern, author, results_count)
    return nil unless allow_sending_to_email?(author, owner)

    @header_text = "Dry run results for \"#{custom_pattern[:name]}\" are ready"
    @icon = "existing-vulnerability.png"
    @title = "Dry run found #{results_count} #{"match".pluralize(results_count) }"

    @owner = owner
    @owner_scope = get_friendly_owner_scope(owner_scope)
    @custom_pattern_edit_path = get_dry_run_view_path(owner, owner_scope, custom_pattern[:id])
    @custom_pattern_name = custom_pattern[:name]
    @owner_name = get_owner_name(owner, owner_scope)
    @footer_links = get_footer_links

    subject = "[#{@owner_name}] "
    subject += "Custom pattern dry run scan finished"

    message_id = generate_dry_run_message_id(@owner_name, custom_pattern[:id], Time.new.to_i)
    email_headers = summary_email_headers(message_id)
    email_headers["X-GitHub-Reason"] = "secret-scanning-custom-pattern-dry-run"
    headers(email_headers)

    premail(
      from: github,
      to: user_email(author, GitHub.newsies.email(author, owner)),
      subject: subject,
    )
  end

  def perform_custom_pattern_dry_run_scan_failed(owner, owner_scope, custom_pattern, author)
    return nil unless allow_sending_to_email?(author, owner)

    @header_text = "Dry run for \"#{custom_pattern[:name]}\" failed"
    @icon = "token-scanning.png"
    @title = "Dry run failed"
    @owner = owner

    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]
    @owner_name = get_owner_name(owner, owner_scope)

    @owner_scope = get_friendly_owner_scope(owner_scope)
    @custom_pattern_name = custom_pattern[:name]
    @custom_pattern_edit_path = get_dry_run_view_path(owner, owner_scope, custom_pattern[:id])

    subject = "[#{@owner_name}] "
    subject += "Custom pattern dry run scan failed"

    message_id = generate_dry_run_message_id(@owner_name, custom_pattern[:id], Time.new.to_i)
    email_headers = summary_email_headers(message_id)
    email_headers["X-GitHub-Reason"] = "secret-scanning-custom-pattern-dry-run"
    headers(email_headers)

    premail(
      from: github,
      to: user_email(author, GitHub.newsies.email(author, owner)),
      subject: subject,
    )
  end

  # owner is either an org, repo, or business, owner scope is a flag that tells us which one it is.
  def get_dry_run_view_path(owner, owner_scope, custom_pattern_id)
    case owner_scope
    when :repository_scope
      show_custom_pattern_path(id: custom_pattern_id, repository: owner, user_id: owner.owner.display_login)
    when :organization_scope
      settings_org_security_analysis_show_custom_pattern_path(id: custom_pattern_id, organization_id: owner.display_login)
    when :business_scope
      settings_business_show_custom_pattern_enterprise_path(id: custom_pattern_id, slug: owner.slug)
    end
  end

  def get_owner_name(owner, owner_scope)
    case owner_scope
    when :repository_scope
      owner.readonly_name_with_display_owner
    when :organization_scope, :business_scope
      owner.display_login
    end
  end

  def get_friendly_owner_scope(owner_scope)
    case owner_scope
    when :repository_scope
      "repository"
    when :organization_scope
      "organization"
    when :business_scope
      "business"
    end
  end

  def get_footer_links
    [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]
  end

  # When handling results that come from the token-scanning-service,
  # results come in as an array of hashes grouped by their token
  # type.
  def find_first_result(results)
    if results.first.is_a?(Hash)
      return results
        .flat_map { |t| t[:tokens] }
        .map { |t| t[:number] }
        .min
    end

    results.first.number
  end

  # When handling results that come from the token-scanning-service,
  # results come in as an array of hashes grouped by their token
  # type.
  def find_latest_result(results)
    if results.first.is_a?(Hash)
      return results
        .flat_map { |t| t[:tokens] }
        .map { |t| t[:number] }
        .max
    end

    results.first.number
  end

  # The "References:" field in the email contains the Message-IDs of all the replies in the thread.
  # As a heuristic, we pick the previous 5 alert numbers as long as they are positive.
  def generate_summary_references(repo, result_number)
    summary_references = []
    (result_number - 5).upto(result_number - 1).each do |num|
      next unless num > 0
      summary_references << generate_summary_message_id(repo, num)
    end

    summary_references
  end

  # Message-Id needs to be globally unique
  def generate_summary_message_id(repo, result_number)
    "<secret-scanning-summary/#{@repo.readonly_name_with_display_owner}/#{result_number}@#{GitHub.urls.host_name}>"
  end

  def generate_alert_summary_message_id(repo, result_number)
    "<secret-scanning-alert-summary/#{@repo.readonly_name_with_display_owner}/#{result_number}@#{GitHub.urls.host_name}>"
  end

  def generate_dry_run_message_id(owner_name, custom_pattern_id, scan_id)
    "<secret-scanning-dry-run/#{owner_name}/#{custom_pattern_id}/#{scan_id}@#{GitHub.urls.host_name}>"
  end

  def generate_initial_backfill_message_id(owner_name, job_group_id)
    "<secret-scanning-initial-backfill/#{owner_name}/#{job_group_id}@#{GitHub.urls.host_name}>"
  end

  # Mimic Newsies headers to be more GitHub-y and to thread related emails.
  #
  # See: Newsies::Emails::Message#headers

  def summary_email_headers(message_id, references = [])
    email_headers = {
      "Message-Id" => message_id,

      "X-GitHub-Sender" => GitHub.trusted_oauth_apps_org_name,
      "X-GitHub-Reason" => "secret-scanning-alert",
    }

    if references.any?
      email_headers["In-Reply-To"] = references.last
      email_headers["References"] = references.join(" ")
    end

    email_headers
  end

  def leaked_mail_headers(user)
    message_id = "<secret-scanning-leaked-token-event/#{user.display_login}@#{GitHub.urls.host_name}>"
    {
      "Message-Id" => message_id,

      "X-GitHub-Sender" => GitHub.trusted_oauth_apps_org_name,
      "X-GitHub-Recipient" => user.display_login,
      "X-GitHub-Reason" => "secret-scanning-alert",
    }
  end

  sig { params(results: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T.untyped]) }
  def alerts_to_list(results)
    return results unless results.first.is_a?(Hash)

    results.map do |result|
      result[:tokens].map do |token|
        # token is a hash that is like Hydro::Schemas::Github::V1::TokenScanNotify::TokenGroup::Token but does not
        # really have this type.
        token = T.let(token, T::Hash[Symbol, T.untyped])
        token[:type] = result[:type]
        token[:first_location_text] = alert_location_text(token[:first_location])
        Token.new(token, @repo)
      end
    end.flatten
  end

  # This uses the location content type to determine the alert text
  def alert_location_text(location)
    case location[:content_type]
    when :REPOSITORY_BLOB, :WIKI_BLOB
      "Secret detected in #{location[:path]}#L#{location[:start_line]} • commit #{location[:commit_oid][0..7]}"
    when :ISSUE_TITLE, :ISSUE_BODY, :ISSUE_COMMENT
      "Secret detected in issue ##{location[:content_number]}"
    when :DISCUSSION_TITLE, :DISCUSION_BODY, :DISCUSSION_COMMENT
      "Secret detected in discussion ##{location[:content_number]}"
    when :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY, :PULL_REQUEST_COMMENT, :PULL_REQUEST_REVIEW, :PULL_REQUEST_TIMELINE_COMMENT, :PULL_REQUEST_REVIEW_COMMENT
      "Secret detected in pull request ##{location[:content_number]}"
    end
  end

  def results_path(**params)
    repository_token_scanning_results_path(@repo.owner, @repo, params)
  end

  class Token
    attr_reader :number, :first_location, :first_location_text, :label, :type

    def initialize(token, repository)
      @number = token[:number]
      @first_location = TokenLocation.new(token[:first_location])
      @first_location_text = token[:first_location_text]
      @label = token[:label]
      @type = token[:type]
    end

    def found_in_archive?
      false
    end
  end

  class TokenLocation
    attr_reader :commit_oid, :path, :start_line, :content_type, :content_number, :content_id

    def initialize(location)
      @commit_oid = location[:commit_oid]
      @path = location[:path]
      @start_line = location[:start_line]
      @content_type = location[:content_type]
      @content_number = location[:content_number]
      @content_id = location[:content_id]
    end
  end
end
