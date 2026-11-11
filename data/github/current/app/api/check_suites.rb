# typed: true
# frozen_string_literal: true

class Api::CheckSuites < Api::App
  include ReceiveSchemaWithOpenApi

  # Get a check suite.
  get "/repositories/:repository_id/check-suites/:check_suite_id", operation_id: "checks/get-suite" do
    repo = find_repo!

    control_access :read_check_suite,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_suite = CheckSuite.find_by(id: params[:check_suite_id])
    record_or_404(check_suite)
    deliver_error! 404 if repo.id != T.must(check_suite).repository_id

    deliver :check_suite_hash, check_suite
  end

  # List check suites for a ref.
  get "/repositories/:repository_id/commits/*/check-suites", operation_id: "checks/list-suites-for-ref" do
    repo = find_repo!

    control_access :read_check_suite,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ref = params[:splat].first
    head_sha = repo.ref_to_sha(ref)
    return deliver_error 404 if head_sha.blank?
    find_commit!(repo, ref, @documentation_url)

    check_suites = CheckSuite.where(head_sha: head_sha, repository_id: repo.id)
    if id = params[:app_id].presence
      check_suites = check_suites.for_app_id(id)
    end
    if name = params[:check_name].presence
      check_suites = check_suites.with_check_run_named(name, repo.id)
    end
    check_suites = paginate_rel(check_suites)
    CheckSuite.prefill_pushes(check_suites: check_suites, repository: repo)
    GitHub::PrefillAssociations.prefill_associations(check_suites, [:creator, :github_app, :repository], available_records: [repo])

    deliver :check_suites_hash, { check_suites: check_suites, total_count: check_suites.total_entries }
  end

  # Set preferences for check suites on a repository
  patch "/repositories/:repository_id/check-suites/preferences", operation_id: "checks/set-suites-preferences" do
    @accepted_scopes = %w(repo)


    repo = find_repo!
    # Return forbidden message about authentication, when the user could otherwise admin the repo
    if can_access_repo?(repo)
      set_forbidden_message "You must authenticate with a personal access token, or basic auth, or via a GitHub App in order to change check suite permissions.".freeze
    end

    control_access :set_check_suite_preferences,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("check-suite-preference", "update")

    auto_trigger_checks = data.fetch("auto_trigger_checks", [])

    auto_trigger_checks.each do |preference|
      app = Integration.find_by(id: preference["app_id"])
      if app && allowed_to_modify_app?(app_id: app.id) && Apps::Privileged.capable?(:modifies_check_suite_preferences, app: app)
        repo.set_auto_trigger_checks(actor: current_user, app: app, value: preference["setting"].to_s)
      else
        deliver_error!(403, message: "Invalid app_id `#{preference["app_id"]}` - check suite can only be modified by the GitHub App that created it.")
      end
    end

    deliver :check_suite_preferences_hash, repo
  end

  # Create a Check Suite
  post "/repositories/:repository_id/check-suites", operation_id: "checks/create-suite" do
    repo = find_repo!

    control_access :write_check_suite,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("check-suite", "create-legacy")

    # Temporarily cover all bases while old fields are transitioned out
    # see https://github.com/github/ecosystem-api/issues/1142
    data["sha"]         ||= data["head_sha"]
    data["head_sha"]    ||= data["sha"]

    data["head_sha"] = find_commit!(repo, data["head_sha"], @documentation_url).oid

    push = Repositories.domain.pushes.by_repo_id_and_after(after: data["head_sha"], repository_id: repo.id)

    GitHub.dogstats.increment("checks.create_suite.nil_push", tags: ["where:rest"]) unless push

    new_check_suite_attrs = {
      head_sha: data["head_sha"],
      github_app: current_integration,
      push_id: push&.id,
      external_id: data["external_id"],
      head_branch: push&.branch_name,
      repository: repo,
    }

    result = CheckSuite.find_or_create_for_integrator(new_check_suite_attrs)

    # preserve historical special case for this kind of error
    if result.duplicate_for_sha?
      deliver_error! 422,
                   message: "A CheckSuite already exists for this sha",
                   documentation_url: @documentation_url
    elsif result.success?
      status = result.existing? ? 200 : 201
      deliver :check_suite_hash, result.record, status: status
    else
      deliver_error! 422,
        errors: result.errors,
        documentation_url: @documentation_url
    end
  end

  # Rerequest a check suite
  post "/repositories/:repository_id/check-suites/:check_suite_id/rerequest", operation_id: "checks/rerequest-suite" do
    # Introducing strict validation of the check-suite.rerequest
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("check-suite", "rerequest", skip_validation: true)

    repo = find_repo!

    control_access :request_check_suite,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_suite = CheckSuite.find_by(id: params[:check_suite_id])
    record_or_404(check_suite)

    check_suite = T.must(check_suite)
    deliver_error! 404 if repo.id != check_suite.repository_id

    unless allowed_to_modify_app?(app_id: check_suite.github_app_id)
      deliver_error!(403, message: "Invalid check_suite_id `#{params[:check_suite_id]}`")
    end

    only_failed_check_suites = data["only_failed_checks"] || false

    begin
      check_suite.rerequest(actor: current_user, only_failed_check_suites: only_failed_check_suites)
      deliver_empty status: 201
    rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
      deliver_error!(403, message: "Unable to re-run this check suite because it was created over a month ago.")
    rescue CheckSuite::AlreadyRerunningError
      deliver_error!(403, message: "This check suite is already re-running.")
    rescue CheckSuite::DisabledWorkflowError
      deliver_error!(403, message: "Unable to re-run disabled workflow")
    rescue CheckSuite::NotRerequestableError
      deliver_error!(403, message: "This check suite is not rerequestable")
    end
  end

  private

  # Can they see that the repo exists?
  def can_access_repo?(repo)
    return true if repo.public?
    repo.pullable_by?(current_user) && scope?(current_user, "repo")
  end
end
