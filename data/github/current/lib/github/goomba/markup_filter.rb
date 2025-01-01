# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # The MarkupFilter wraps the GitHub::Markup gem and makes it usable in a
  # WarpPipe. The only caveat with this filter is that it takes a git
  # blob as the input - either as a gitrpc blob Hash or a TreeEntry (or
  # compatible) object.
  class MarkupFilter < InputFilter

    def self.cache_key(context)
      GitHub::HTML::MarkupFilter.cache_key(context)
    end

    def call(input)
      GitHub::HTML::MarkupFilter.new(input, context, result).call
    end
  end
end
