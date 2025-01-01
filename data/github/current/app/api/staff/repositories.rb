# typed: true
# frozen_string_literal: true

class Api::Staff::Repositories < Api::Staff::App
  # Get the latest page build result.
  #
  # Used by `gh-pages latest REPO`
  get "/staff/repos/:user/:repo/pages/builds/latest", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/stafftools"
    repo = this_repo

    deliver_error!(404) unless page = repo.page
    deliver_error!(404) unless build = page.builds.first
    deliver :page_build_hash, build, repo: repo, last_modified: calc_last_modified_for_object(build)
  end

  # Get page information.
  #
  # Used by `gh-pages cname REPO`
  get "/staff/repos/:user/:repo/pages", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/stafftools"
    repo = this_repo

    deliver_error!(404) unless page = repo.page
    deliver :page_hash, page, repo: repo, last_modified: calc_last_modified_for_object(repo)
  end

  # Start a new page build.
  #
  # Used by `gh-pages build REPO`
  post "/staff/repos/:user/:repo/pages/builds", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/stafftools"
    repo = this_repo

    if repo.has_gh_pages?
      build_as = repo.gh_pages_rebuilder(current_user)
      if build_as
        if repo.rebuild_pages(build_as)
          pending = { status: "queued", url: "#{@current_url}/latest" }
          deliver_raw pending, status: 201
        else
          deliver_error 202, message: "A build is already in progress."
        end
      else
        deliver_error 403, message: "Cannot find a user to build the page as."
      end
    else
      deliver_error 404, message: "The repository cannot build Pages."
    end
  end
end
