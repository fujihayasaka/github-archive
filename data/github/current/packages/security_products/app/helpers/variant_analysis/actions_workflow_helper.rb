# typed: true
# frozen_string_literal: true

module VariantAnalysis::ActionsWorkflowHelper
  include VariantAnalysis::StorageHelper
  include CodeScanningQueriesHelper

  class InputsTooLarge < StandardError; end
  class UnableToLaunch < StandardError; end
  class InvalidActionRepoRef < StandardError; end

  # ID of the github/codeql-variant-analysis-action repo
  CODEQL_VARIANT_ANALYSIS_ACTION_REPO_ID = 392390549

  # Path of the workflow file within github/codeql-variant-analysis-action
  WORKFLOW_FILE_PATH = "variant-analysis-workflow.yml"

  # Placeholder for the variant analysis action ref in the workflow file
  WORKFLOW_REF_PLACEHOLDER = "CODEQL_VARIANT_ANALYSIS_ACTION_REF"

  # Public: Creates a multi-repo variant analysis actions workflow run.
  #
  # variant_analysis - The variant analysis to create the workflow run for.
  # instructions_url - The signed URL of the instructions file.
  # action_repo_ref  - Ref of codeql-variant-analysis-action to use during workflow run.
  # repo_count       - The number of repos the variant analysis will run against.
  #
  # Returns the worklfow run id.
  # Raises InputsTooLarge if the Action inputs are too large.
  # Raises UnableToLaunch if for some reason we were unable to launch the workflow run.
  def create_workflow_run(
    variant_analysis:,
    instructions_url:,
    action_repo_ref:,
    repo_count:
  )

    workflow_name = workflow_long_name(variant_analysis.query_language, repo_count)
    inputs = {
      "workflow_name": workflow_name,
      "language": variant_analysis.query_language,
      "instructions_url": instructions_url,
      "query_pack_url": create_signed_url(variant_analysis.query_pack_path, 24.hours),
      "variant_analysis_id": variant_analysis.id.to_s,
      "action_repo_ref": action_repo_ref,
      "signed_auth_token": VariantAnalysis::SignedAuthToken.create_update_token(variant_analysis),
    }

    if inputs.to_json.length > MYSQL_TEXT_FIELD_LIMIT
      raise InputsTooLarge, "Action workflow inputs too large"
    end

    workflow = dynamic_workflow_yaml(action_repo_ref, variant_analysis.actor)

    result = ActiveRecord::Base.connected_to(role: :writing) do
      variant_analysis.controller_repo.run_dynamic_workflow(
        actor: variant_analysis.actor,
        workflow: workflow,
        ref: variant_analysis.controller_repo.default_branch,
        inputs: inputs,
        workflow_name: "CodeQL query",
        slug: "queries",
        integration_name: "codeql",
        entry_point: :variant_analysis_actions_helper_run_dynamic_workflow
      )
    end

    unless result
      raise UnableToLaunch, "Unable to launch remote query run. No response from launch run_dynamic_workflow."
    end

    unless result.call_succeeded?
      message = result&.options ? result.options[:message] : nil
      raise UnableToLaunch, "Unable to launch remote query run. #{message}"
    end

    result.value.workflow_run_id
  end

  # Public: Checks whether the ref provided for the repository running a variant analysis GitHub action is valid.
  #
  # action_repo_ref - The ref of othe repo to check.
  #
  # Raises InvalidActionRepoRef if the user is non-priviledged and the ref is not "main", or
  #   if the user is priviledged but the ref is not in the codeql-variant-analysis-action repo.
  def check_for_valid_ref(action_repo_ref:, user:)
    return if action_repo_ref == "main"

    if user.feature_enabled?(:mrva_allow_non_default_action_ref)
      if !branch_exists(codeql_variant_analysis_action_repo, action_repo_ref)
        raise InvalidActionRepoRef, "Invalid ref provided. Please provide a ref that exists on the github/codeql-variant-analysis-action repo."
      end
    else
      raise InvalidActionRepoRef, "Invalid ref provided. You are only allowed to use `main`."
    end
  end

  def branch_exists(repo, ref)
    repo.refs.find(ref)
  end

  def create_repo_nwo_chunks(variant_analysis, repo_nwos)
    max_job_count = 100

    # Chunk the repositories across at most max_job_count jobs
    chunk(repo_nwos, max_job_count)
  end

  # Read the workflow file from the variant analysis action repo if the user
  # is allowed to and the ref is not "main", but if that isn't true or the file
  # is not found then fall back to the default workflow.
  def dynamic_workflow_yaml(ref, user)
    if ref == "main" || !user.feature_enabled?(:mrva_allow_non_default_action_ref)
      return dynamic_workflow_yaml_from_file("main")
    end

    head = codeql_variant_analysis_action_repo.heads.find(ref)
    if head.nil?
      # The ref is checked when the variant analysis is created, so this means it has been deleted since then
      raise InvalidActionRepoRef, "Invalid ref provided. Please provide a ref that exists on the github/codeql-variant-analysis-action repo."
    end

    blob = codeql_variant_analysis_action_repo.blob(head.target.sha, WORKFLOW_FILE_PATH)
    return blob.data.to_s unless blob.nil?

    dynamic_workflow_yaml_from_file(head.target.sha)
  end

  private

  def codeql_variant_analysis_action_repo
    @codeql_variant_analysis_action_repo ||= Repository.find_by(id: CODEQL_VARIANT_ANALYSIS_ACTION_REPO_ID)
  end

  def workflow_long_name(language, repo_count)
    "CodeQL query - #{language} query on #{repo_count} repositories"
  end

  def dynamic_workflow_yaml_from_file(ref)
    content = File.read(File.join(File.dirname(__FILE__), "workflow.yml"))
    content.gsub(WORKFLOW_REF_PLACEHOLDER, ref)
  end
end
