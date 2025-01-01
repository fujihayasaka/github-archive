# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveHookTargets::ShowPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :query, :selected_file, :selected_repository_id
  FILES_LIMIT = 10000

  def repositories
    @repositories = PreReceiveHook::RepositoryFilter.new(current_user, query).results
  end

  def environments
    PreReceiveEnvironment.all
  end

  def files
    return @files if @files

    repo = if selected_repository_id
      if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        T.cast(Repositories.domain.by_id(selected_repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      else
        Repository.find_by(id: selected_repository_id)
      end
    end

    return @files = [] unless repo

    branch = repo.default_branch
    sha = repo.ref_to_sha(branch)
    return @files = [] if sha.nil?
    @files = repo.tree_file_list(sha)
  end

  def files_limit_reached
    files.count > FILES_LIMIT
  end

  def repository_display(repo)
    repo.name_with_display_owner
  end
end
