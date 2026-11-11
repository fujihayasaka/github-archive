# typed: strict
# frozen_string_literal: true

# WorkflowConfigLoader loads workflow files for a repository that are relevant
# to code coverage configuration. It returns a list of active workflows with
# their display names and edit URLs, gated behind the code-coverage-enablement
# feature flag.
class CodeQuality::WorkflowConfigLoader
  sig { params(repository: Repository).void }
  def initialize(repository:)
    @repository = T.let(repository, Repository)
  end

  sig { returns(T::Array[T::Hash[String, String]]) }
  def workflow_files
    return [] unless CodeCoverage.workflow_configuration_enabled?(@repository)

    # Only include active repository workflow files under .github/workflows/:
    # exclude required/external workflows (for example, org-level workflows) and
    # dynamic/non-repo workflows that are not backed by a repository file.
    @repository.workflows.active.non_required.prod.map do |workflow|
      {
        "name" => workflow.name.presence&.to_s || File.basename(workflow.path),
        "editUrl" => edit_workflow_path(workflow.path),
      }
    end
  end

  private

  sig { params(workflow_path: String).returns(String) }
  def edit_workflow_path(workflow_path)
    owner_login = T.must(@repository.owner).display_login
    repo_name = @repository.name
    default_branch = @repository.default_branch
    "/#{owner_login}/#{repo_name}/edit/#{default_branch}/#{workflow_path}"
  end
end
