# typed: true
# frozen_string_literal: true

# Shared base class for internal API endpoints deliverying info about git content.
class Api::Internal::GitContent < Api::Internal

  include Api::App::ContentHelpers
  include RawBlob::ContentHelpers

  require_api_semantic_version "hyperion"

  def repository_or_gist_or_404(repo_or_gist)
    if repo_or_gist.is_a?(Repository)
      repository_or_404(repo_or_gist)
    else
      gist_or_404(repo_or_gist)
    end
  end

  def find_repo
    @current_repo ||= ActiveRecord::Base.connected_to(role: :reading) do
      repo = Repository.nwo(params[:user].to_s, params[:repo].to_s)
      repo ||= RepositoryRedirect.find_redirected_repository("#{params[:user]}/#{params[:repo]}")
      repo = nil if repo && repo.access.disabled?

      repo
    end
  end

  def verify_not_spammy
    return unless (path = params[:user].to_s).present?
    return unless repo_owner = User.find_by_login(path)

    if repo_owner.spammy?
      return if repo_owner == @current_user # Spammy repo owner can download their own repo
      deliver_error! 403, message: "User #{repo_owner} flagged as spammy"
    end
  end

  # Check if the current repo is allowed to open the wiki feature
  def verify_wiki_access_allowed
    unless current_repository.plan_supports?(:wikis)
      deliver_error! 403, message: "Upgrade to GitHub Pro or make this repository public to enable this feature."
    end
  end

  def rate_limited_route?
    false
  end

  # We'll handle private mode by enforcing a ?token.  #current_user is not set
  # yet because we need to parse out the branch and path for the remote auth
  # scope.
  def protect_access_to_enterprise_hosts
  end
end
