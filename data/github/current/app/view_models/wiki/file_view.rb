# typed: true
# frozen_string_literal: true

module Wiki
  class FileView < Diff::FileView
    include UrlHelpers
    include UrlHelper
    include GitHub::RouteHelpers

    def initialize(*args)
      self.hidden_render_diff = true
      super
    end

    def current_repository
      repository.repository
    end

    def prepare_for_rendering!
      # we don't want to do any render preparation in wikis as it can mutate the diff
      nil
    end

    def deferred_syntax_url
      # We don't currently support deferred syntax highlighting for wikis
      nil
    end

    def deferred_syntax_inputs
      {}
    end

    def diff_blob_path(base, head)
      if diff.deleted?
        wiki_page_path(GitHub::Unsullied::Page.to_param(diff.a_path), diff.a_sha)
      else
        wiki_page_path(GitHub::Unsullied::Page.to_param(diff.b_path), diff.b_sha)
      end
    end
  end
end
