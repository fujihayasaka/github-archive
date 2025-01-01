# typed: true
# frozen_string_literal: true

module SvgHelper
  include Kernel

  # This method uses the inline_svg gem to embed SVG documents in Rails views.
  # For all helper options, see: https://github.com/jamesmartin/inline_svg/#options.
  #
  # Accessibility Considerations
  # - If the SVG provides important context for the user, you must provide a text alternative. There are multiple approaches to this, but this helper makes it easy
  #   to add a <title> element to the SVG via the `title` option.
  # - If the SVG is purely decorative or duplicates information conveyed by adjacent text, set `aria_hidden: true` to hide it from assistive technologies.
  # - For simple SVGs, such as an icon, set `aria: true` to apply relevant accessibility attributes. https://github.com/jamesmartin/inline_svg#accessibility
  # - For complex, interactive SVGs, such as a chart, please assign `github/accessibility-reviewers` for review.
  #
  # Reach out to @github/accessibility or slack #accessibility for help.
  def svg(*args)
    options = args.extract_options!
    raise ArgumentError, "`alt` is not a valid keyword. Did you mean `title`? " if options.include?(:alt)

    T.unsafe(self).inline_svg(*args, **options)
  end
end
