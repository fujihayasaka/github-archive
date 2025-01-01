# typed: false
# frozen_string_literal: true

module DiffViewHelper
  # This class should only be applied to the <body> element.
  # For all other elements, use Primer width classes instead.
  # See https://primer.style/css/utilities/layout#width-and-height
  FULL_WIDTH_BODY_CLASS_NAME = "full-width"

  # Determine the current diff view for the current request.
  #
  # Returns :unified or :split Symbol.
  def diff_view
    return @diff_view if defined?(@diff_view)
    @diff_view = \
      if params[:diff] == "split"
        :split
      elsif params[:diff] == "unified"
        :unified
      elsif logged_in? && current_user.split_diff_preferred && !mobile?
        :split
      else
        :unified
      end
  end

  # Detect initial body class for a page that will render a diff.
  #
  # As an optimization, we want the body.full-width class to be set on the initial
  # render if the page should be rendered full width. Otherwise, the browser needs to
  # wait until JS kicks in and adds the body class. This causes a jarring
  # relayout a few seconds after the initial paint.
  #
  # The downside to this logic is that we have to duplicate when the body class
  # should be added in Ruby and in JS.
  #
  # See app/assets/modules/github/diffs/split.ts for the other half.
  #
  # force_full_width (optional) - Boolean override to force full width layout
  #
  # Returns "full-width" String or nil.
  def diff_body_class(force_full_width: false)
    if split_diff? || force_full_width
      FULL_WIDTH_BODY_CLASS_NAME
    end
  end

  # Deprecated: Determine if current diff view is "Split".
  #
  # Prefer checking diff_view directly.
  #
  # Returns Boolean.
  def split_diff?
    return @split_diff if defined?(@split_diff)
    @split_diff = diff_view == :split
  end

  # Determines if the current mode includes whitespace.
  #
  # Returns Boolean.
  def show_whitespace?
    return @whitespace if defined?(@whitespace)
    @whitespace = params[:w] != "1"
  end
end
