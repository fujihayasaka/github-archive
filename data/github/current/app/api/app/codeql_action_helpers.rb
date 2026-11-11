# typed: true
# frozen_string_literal: true

module Api::App::CodeqlActionHelpers
  include Api::App::CodeScanningHelpers
  include Api::App::CodeScanningCategoryHelper

  # Check that the current user has read access to the given repo, and that
  # the CodeQL Action is usable in that repo. This function returns without
  # an error if the CodeQL Action is usable.
  #
  # Use "forbid" to give a 403 vs a 404 response in the case that the user
  # does not have read access to the repository.
  sig { params(repo: Repository, forbid: T::Boolean).void }
  def ensure_read_access_and_codeql_action_enabled!(repo, forbid: false)
    can_read = access_allowed? :v4_get_repo,
                                resource: repo,
                                repo: repo,
                                allow_integrations: true,
                                allow_user_via_granular_actor: true

    deliver_error!(forbid ? 403 : 404) if !can_read

    # Allow if Code Quality is available
    if CodeQuality.available?(repo)
      return
    end

    # Finally, check if Code Scanning is available
    ensure_code_scanning_enabled!(repo)
  end
end
