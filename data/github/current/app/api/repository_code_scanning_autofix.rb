# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningAutofix < Api::App
  include Api::App::CodeScanningHelpers

  get "/repositories/:repository_id/code-scanning/alerts/:alert_number/autofix", operation_id: "code-scanning/get-autofix" do
    repo = find_repo!

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_valid_alert_number!(alert_number)

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    begin
      autofix_suggestion = CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
        repository: repo,
        alert_numbers: [alert_number],
        head_commit_oid: repo.default_branch_ref.commit.oid,
      )[alert_number]
    rescue CodeScanning::AutofixError
      deliver_code_scanning_unavailable_error!
    end

    deliver_error! 404, message: "No suggested fix found" if autofix_suggestion.nil?

    deliver :code_scanning_autofix_hash, {
      status: status_mapping(autofix_suggestion.state, autofix_suggestion.suggested_fix&.outdated),
      description: autofix_suggestion.suggested_fix&.description,
      started_at: autofix_suggestion.created_at
    }
  end

  post "/repositories/:repository_id/code-scanning/alerts/:alert_number/autofix", operation_id: "code-scanning/create-autofix" do
    repo = find_repo!

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_valid_alert_number!(alert_number)

    control_access :write_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_write_message

    deliver_error_if_archived!(repo)

    default_branch_ref = repo.default_branch_ref
    deliver_error! 404 unless default_branch_ref.present?

    ref_names_bytes = Array(default_branch_ref.qualified_name.b)
    head_commit_oid = default_branch_ref.commit.oid

    alert = GitHub::Turboscan.alert(
      repository_id: repo.id,
      number: alert_number,
    )&.data&.result

    # Deliver a 422 if **any** of the following are true:
    deliver_error! 422, message: "Alert is not present on the default ref." unless alert.present?
    deliver_error! 422, message: "Alert is not open on the default ref." if alert.is_fixed || alert.resolution != :NO_RESOLUTION
    deliver_error! 422, message: "Cannot determine if alert is supported for autofix." unless alert.tool.present? && alert.rule.present?
    tool_name = T.must(alert.tool).name
    sarif_identifier = T.must(alert.rule).sarif_identifier
    deliver_error! 422, message: "Alert is not supported by autofix." unless
      CodeScanning::Autofix.enabled_for_tool?(repo, tool_name) &&
      CodeScanning::Autofix.is_rule_supported?(repo, tool_name, sarif_identifier)

    # The alert looks good, try to generate a new autofix
    generate_response = CodeScanning::AutofixSuggestion.generate(
      repository: repo,
      alert_numbers: Array(alert_number),
      ref_names_bytes:,
      source: :SUGGESTED_FIX_SOURCE_ONDEMAND_API
    )
    if generate_response.blank? || generate_response.error.present?
      deliver_code_scanning_unavailable_error!
    end

    # Now try to fetch the autofix. This may fetch the newly generated autofix, or an existing one.
    autofix_suggestion = begin
      # Fetch a relevant existing suggested fix
      CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
        repository: repo,
        alert_numbers: [alert_number],
        head_commit_oid:,
        ref_names_bytes:
      ).to_h[alert_number]
    rescue CodeScanning::AutofixError
      # An error here is unexpected and we cannot recover
      deliver_code_scanning_unavailable_error!
    end

    if autofix_suggestion.present?
      case autofix_suggestion.state
      when :SUGGESTED_FIX_ALERT_STATE_INVALID, :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
        deliver_error! 422, message: "The autofix for this alert is invalid."
      when :SUGGESTED_FIX_ALERT_STATE_PENDING
        # Assume we have just started to generate this autofix.
        # In some cases this may be an autofix that was generated from a previous request,
        # but this assumption reduces complexity for a "good enough" approximation.
        deliver! :code_scanning_autofix_hash, {
          status: status_mapping(autofix_suggestion.state, false),
          description: nil,
          started_at: autofix_suggestion.created_at
        }, status: 202
      else
        deliver! :code_scanning_autofix_hash, {
          status: status_mapping(autofix_suggestion.state, autofix_suggestion.suggested_fix&.outdated),
          description: autofix_suggestion.suggested_fix&.description,
          started_at: autofix_suggestion.created_at
        }
      end
    end

    # We shouldn't expect to end up here, but add a catch-all for unexpected errors
    # (e.g. unexpected state in the turboscan db)
    deliver_code_scanning_unavailable_error!
  end

  post "/repositories/:repository_id/code-scanning/alerts/:alert_number/autofix/commits", operation_id: "code-scanning/commit-autofix" do
    repo = find_repo!

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_valid_alert_number!(alert_number)

    control_access :create_commit,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    ensure_repo_content!(repo)
    ensure_repo_writable!(repo)

    deliver_error_if_archived!(repo)

    data = receive_with_openapi
    provided_ref = data&.dig("target_ref")
    target_ref = if provided_ref.present?
      # Find an existing branch if provided or return nil
      repo.heads.find(provided_ref)
    else
      begin
        # Create a new branch if no target_ref was provided
        repo.heads.create(new_branch_name(alert_number, repo), repo.default_branch_ref.commit.oid, current_user)
      rescue Git::Ref::InvalidName
        deliver_error! 422, message: "Invalid branch name"
      rescue Git::Ref::ExistsError
        deliver_error! 422, message: "Branch already exists"
      rescue Git::Ref::RepositoryRuleViolationError
        deliver_error! 422, message: "Could not create branch as repository rules prevent it"
      rescue Git::Ref::UpdateError
        deliver_error! 422, message: "Could not create branch"
      rescue GitRPC::ObjectMissing
        deliver_error! 422, message: "Object does not exist"
      end
    end

    deliver_error! 422, message: "Provided target does not exist" if target_ref.nil?

    begin
      autofix_suggestion = CodeScanning::AutofixSuggestion.fetch_applicable_suggested_fix_alerts(
        repository: repo,
        alert_numbers: [alert_number],
        head_commit_oid: target_ref.commit.oid,
      )[alert_number]
    rescue CodeScanning::AutofixError => e
      deliver_error! 404, message: e.message
    end

    status = status_mapping(autofix_suggestion.state, autofix_suggestion.suggested_fix.outdated)
    deliver_error! 422, message: "Suggested fix is not valid." if status != "success"

    begin
      result = CodeScanning::AutofixCommit.create(
        alert_number:,
        commit_message: data["message"],
        repository: repo,
        ref: target_ref,
        author: current_user,
        suggested_fix: CodeScanning::AutofixSuggestion.new(autofix_suggestion.suggested_fix),
        reflog_via: "apply autofix suggestion from on demand api"
      )

      sha, _branch_name, _error = result

      # the `b` method on target_ref changes the encoding to ASCII-8BIT
      GitHub::Turboscan.create_alert_links(
        repository_id: repo.id,
        links: [
          {
            alert_number: alert_number,
            ref_name_bytes: target_ref.qualified_name.b,
          }
        ]
      )
    rescue DiffEntrySuggestedChange::UnprocessableError => e
      deliver_error! 422, message: e.message
    rescue DiffEntrySuggestedChange::NotFoundError => e
      deliver_error! 404, message: e.message
    rescue DiffEntrySuggestedChange::ForbiddenError => e
      deliver_error! 403, message: e.message
    end

    deliver :code_scanning_autofix_commit_hash, {
      target_ref: target_ref.qualified_name,
      sha: sha
    }, status: 201
  end

  private

  def alert_number
    int_id_param!(key: :alert_number)
  end

  def status_mapping(suggested_fix_alert_state, outdated)
    case suggested_fix_alert_state
    when :SUGGESTED_FIX_ALERT_STATE_VALID
      outdated ? "outdated" : "success"
    when :SUGGESTED_FIX_ALERT_STATE_PENDING
      "pending"
    else
      "error"
    end
  end

  def new_branch_name(alert_number, repository)
    name = "alert-autofix-#{alert_number}"
    # Check if the branch already exists
    if repository.heads.find(name)
      # Append a random hex to the branch name if it already exists to create a new one
      name << "-#{SecureRandom.hex(4)}"
    end
    name
  end

  def rate_limit_configuration
    return super unless request.env["github.api.route"] == "POST /repositories/:repository_id/code-scanning/alerts/:alert_number/autofix"
    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::CODE_SCANNING_AUTOFIX_FAMILY,
      self,
    )
  end
end
