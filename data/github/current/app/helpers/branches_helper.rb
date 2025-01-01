# typed: false
# frozen_string_literal: true

module BranchesHelper
  include GitHub::ResilienceMixin

  def link_to_branch_compare(repo, branch_name, options = {})
    label = options.delete(:label) || branch_name.dup.force_encoding("UTF-8").scrub!
    dest  = compare_path repo, branch_name
    dest  = repository_path repo if branch_name == repo.default_branch

    link_to label, dest, options
  end

  # Represents the freshness of a plain JSON list of refs from the repo.  It's
  # tied to `refset_updated_at`, which is incremented whenever the list of refs
  # changes because of a push, so the cache key should perfectly match the
  # underlying thing being cached.
  def ref_list_cache_key(repository: current_repository)
    time = with_database_error_fallback(fallback: Time.current) { repository.refset_updated_at }
    "v0:#{time.to_f}"
  end

  def show_protect_branch_banner?(repo)
    return false unless logged_in?
    return false if current_user.dismissed_repository_notice?("sculk_protect_this_branch", repository_id: repo.id)
    return false unless repo.writable?
    return false unless repo.adminable_by?(current_user)

    branch_protected = repo.protected_branches.any?
    rulesets = RepositoryRuleset.load_for(source: repo, include_parents: true)
    ruleset_protected = !rulesets.none? { |ruleset| ruleset.enabled? || ruleset.source == repo }

    if !(branch_protected || ruleset_protected)
      repo.pull_requests.open_pulls.any? && !repo.archived?
    else # protected by branch protection or ruleset
      false
    end
  end

  def show_protect_this_branch_banner?(branch_name)
    with_database_error_fallback(fallback: false) do
      show_protect_branch_banner?(current_repository) && current_repository.default_branch == branch_name && current_repository.heads.size >= 2
    end
  end
end
