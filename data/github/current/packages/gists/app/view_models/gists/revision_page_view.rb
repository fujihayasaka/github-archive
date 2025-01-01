# typed: true
# frozen_string_literal: true

module Gists
  # Controls the gist revisions view
  # eg https://github.com/gists/defunkt/gist-id/revisions
  class RevisionPageView < ShowPageView
    attr_reader :commits, :params

    def page_title
      "Revisions · #{super}"
    end

    def file_list_views
      Enumerator.new do |yielder|
        commits.each do |commit|
          yielder.yield Gists::FileListView.new(
              commit: commit,
              diffs: commit.diff,
              params: params,
              current_user: current_user,
              commentable: false,
              expandable: false,
            )
        end
      end
    end
  end
end
