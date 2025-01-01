# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_wikis_path(repo)
      expand_nwo_from :wikis_path, repo
    end

    def gh_wiki_path(page, repo = nil)
      if repo
        wiki_path(repo.owner, repo, page)
      else
        expand_nwo_from :wiki_path, page
      end
    end
  end
end
