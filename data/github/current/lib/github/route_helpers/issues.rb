# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_issues_path(repo)
      expand_nwo_from :issues_path, repo
    end

    def gh_issue_path(issue)
      expand_nwo_from :issue_path, issue
    end

    def gh_close_issue_path(issue)
      expand_nwo_from :close_issue_path, issue
    end

    def gh_open_issue_path(issue)
      expand_nwo_from :open_issue_path, issue
    end

    def gh_labels_path(repo)
      expand_nwo_from :labels_path, repo
    end

    def gh_label_path(label, repository = nil)
      repo = repository || label.repository
      "/#{repo.name_with_display_owner}/labels/#{Addressable::URI.encode_component(label.name, Addressable::URI::CharacterClasses::UNRESERVED)}"
    end

    def gh_milestone_path(milestone, repository = nil)
      T.bind(self, T.untyped)
      repo = repository || milestone.repository
      milestone_path(repo.owner_display_login, repo, milestone)
    end

    def gh_milestone_issue_search_path(milestone)
      T.bind(self, T.untyped)
      if milestone.open?
        milestone_query_path(milestone.repository.owner_display_login, milestone.repository, milestone.title)
      else
        issues_path(milestone.repository.owner_display_login, milestone.repository, q: "milestone:#{Search::ParsedQuery.encode_value(milestone.title)}")
      end
    end

    def gh_unsubscribe_issue_path(issue)
      expand_nwo_from :unsubscribe_issue_path, issue
    end

    def gh_subscribe_issue_path(issue)
      expand_nwo_from :subscribe_issue_path, issue
    end
  end
end
