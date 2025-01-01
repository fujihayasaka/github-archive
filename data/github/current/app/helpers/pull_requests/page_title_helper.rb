# typed: true
# frozen_string_literal: true

module PullRequests::PageTitleHelper
  def pull_request_page_title(pull)
    attribution = pull.user ? " by #{pull.user.display_login}" : ""
    "#{pull.title}#{attribution} · Pull Request ##{pull.number} · #{pull.repository.name_with_display_owner}"
  end
end
