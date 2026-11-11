# typed: true
# frozen_string_literal: true

module Gists
  class FileView < Diff::FileView
    include ActionView::Helpers::AssetTagHelper

    def this_gist
      repository
    end

    def diff_blob
      helpers.diff_blob(diff, this_gist)
    end

    def prepare_for_rendering!
      # we don't want to do any render preparation in gists as it can mutate the diff
      nil
    end

    def diff_blob_path(base, head)
      if diff.deleted?
        urls.user_gist_at_revision_path(this_gist.user_param, this_gist, diff.a_sha)
      else
        urls.user_gist_at_revision_path(this_gist.user_param, this_gist, diff.b_sha)
      end
    end

    def display_diff_blob_action_buttons?
      true
    end
  end
end
