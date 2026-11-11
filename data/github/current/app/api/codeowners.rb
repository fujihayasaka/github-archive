# typed: true
# frozen_string_literal: true

module Api
  class Codeowners < App
    get "/repositories/:repository_id/codeowners/errors", operation_id: "repos/codeowners-errors" do
      repo = find_repo!

      control_access :get_codeowners_errors,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ref = params.fetch("ref", repo.default_branch)

      codeowners = Repository::Codeowners.new(repo, ref: ref)

      deliver_error!(404) unless codeowners.exists?

      errors = codeowners.errors + codeowners.owner_errors
      errors.sort_by!(&:line)

      deliver(
        :codeowners_error_list,
        errors: errors,
        path: codeowners.path,
      )
    end
  end
end
