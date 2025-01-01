# typed: true
# frozen_string_literal: true

# We seem to lack a simple way, in the goomba / warp pipe ecosystem,
# to sanitize content without also turning it into html.
# The html pipeline allowed this behavior using the Sanitize gem.
# For example, in the case of the memex filter below, the text string "Change `columnA` to `columnB`"
# will have its backticks stripped because the memex filter doesn't render :code tags.
module GitHub::Goomba
  class SanitizationFilter < InputFilter
    def call(node)
      GitHub::HTML::SanitizationFilter.new(node, @context, @result).call.to_html
    end
  end
end
