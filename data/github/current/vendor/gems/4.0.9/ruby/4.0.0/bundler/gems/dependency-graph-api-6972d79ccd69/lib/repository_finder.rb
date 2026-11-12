require_relative "monolith/repositories"

module RepositoryFinder

  # find_repo takes the nwo and returns a repo or nil
  # if no repo with the nwo exists in the dg-api db,
  # its fetched from the monolith twirp API (see Monolith::Repositories) and saved.
  def find_repo(nwo:)
    repo = Repository.find_by(nwo: nwo)
    return repo if repo.present?

    begin
      resp = monolith_repositories.find_repositories_by_name([nwo])
      return nil if resp.nil? || resp&.first.nil?
      repo = resp.first
    rescue Monolith::TwirpClient::Error => tce
      DependencyGraph.logger.error(message: "repo finder Twirp error", twirp_error: tce.to_s, target_nwo: nwo)
      Failbot.report(tce)
      return nil
    end

    begin
      # Check whether we got a repository with that github_repository_id. This could happen
      # if the repository was renamed and the `nwo` in `dg_repositories` got out of date.
      # If we find an existing repository, we update it with the fresh attributes we just
      # got from the monolith, and if we don't we create a new repository.
      #
      # Note that this would be a textbook use-case for `upsert`, but unfortunately pre-rails 7
      # it does not support timestamp columns (created_at, updated_at) and so it'd be quite annoying to use.
      existing_repo = Repository.find_by(github_repository_id: repo.github_repository_id)
      if existing_repo
        existing_repo.update!(repo.attributes.slice("github_owner_id", "nwo", "public"))
        return existing_repo
      else
        repo.save
        return repo
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end

  def get_gh_repo_id(nwo:)
    find_repo(nwo: nwo)&.github_repository_id
  end

  private
  def monolith_repositories
    Monolith::Repositories.new
  end
end
