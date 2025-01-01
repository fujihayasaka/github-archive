# typed: true
# frozen_string_literal: true

module Gists
  class FileListView < Diff::FileListView
    class Helpers < ViewModel::Helpers
      include ApplicationHelper # provides `user_for_email`
    end

    self.file_view_class = FileView

    def helpers
      @helpers ||= Gists::FileListView::Helpers.new(self)
    end

    def this_gist
      repository
    end

    def commit_author_link
      user = helpers.user_for_email(commit.author_email)

      if commit.author_email == "anonymous@github.com"
        "Anonymous"
      elsif user = helpers.user_for_email(commit.author_email)
        helpers.link_to(user, urls.user_path(user))
      else
        commit.author_name
      end
    end

    def revised_verb
      if renamed?
        "renamed"
      elsif created?
        "created"
      else
        "revised"
      end
    end

    def renamed?
      diffs.size == 1 && diffs.first.renamed?
    end

    def created?
      commit.parent_oids.none?
    end
  end
end
