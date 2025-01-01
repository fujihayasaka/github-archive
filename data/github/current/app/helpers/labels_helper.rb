# typed: true
# frozen_string_literal: true

module LabelsHelper
  extend T::Helpers
  extend T::Sig

  abstract!

  requires_ancestor { ActionView::Helpers::NumberHelper }

  sig { abstract.returns(T.untyped) }
  def current_user; end

  sig { abstract.returns(T.untyped) }
  def current_repository; end

  # Public: The name of the label with `g-emoji` HTML tags instead of raw Unicode emoji or
  # colon-style emoji.
  #
  # name - the name of the label, a String
  # skip_cache - Boolean; whether we should skip trying to load the label name from cache
  #
  # Returns a String, potentially containing `g-emoji` HTML tags.
  def html_label_name(name, skip_cache: false)
    renderer = EmojiHtmlStringRenderer.new(name,
      skip_cache: skip_cache,
      cache_key_prefix: Label::NAME_HTML_CACHE_KEY_PREFIX)
    renderer.to_html
  end

  def can_viewer_convert_current_repos_issues_to_discussions?
    if defined?(@can_viewer_convert_current_repos_issues_to_discussions)
      return @can_viewer_convert_current_repos_issues_to_discussions
    end
    @can_viewer_convert_current_repos_issues_to_discussions =
      current_repository&.can_convert_issues_to_discussions?(current_user)
  end

  def label_issue_count_summary(label)
    count = label.issues_count
    units = if count == 1
      "issue or pull request"
    else
      "issues and pull requests"
    end
    "#{number_with_delimiter(count)} open #{units}"
  end
end
