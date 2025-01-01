# typed: strict
# frozen_string_literal: true

module Discussions
  class EditHistory::DiffComponent < ApplicationComponent
    extend T::Sig

    sig { params(edit: T.any(DiscussionEdit, DiscussionCommentEdit)).void }
    def initialize(edit:)
      @edit = edit
    end

    private

    sig { returns(T.any(DiscussionEdit, DiscussionCommentEdit)) }
    attr_reader :edit

    sig { returns(T::Boolean) }
    def show_footer?
      return false unless logged_in?
      return true if current_user.site_admin?
      edit.viewer_can_delete?(current_user)
    end

    sig { returns(String) }
    memoize def diff_html
      GitHub::HTML::Diff.new(
        GitHub::Goomba::MarkdownPipeline.to_html(edit.diff_before),
        GitHub::Goomba::MarkdownPipeline.to_html(edit.diff)
      ).html
    end
  end
end
