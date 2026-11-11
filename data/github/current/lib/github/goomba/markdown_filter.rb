# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class MarkdownFilter < InputFilter

    EXTENSIONS = %i[
      table
      strikethrough
      tagfilter
      autolink
    ]

    def self.cache_key(context)
      [
        ("skip_tagfilter" if context[:skip_tagfilter]),
        ("gfm" if context.fetch(:gfm, false))
      ].reject(&:blank?).join(":")
    end

    def call(text)
      return "" if text.nil?

      # Use :UNSAFE as we don't want to use cmark-gfm's internal sanitiser. (See
      # https://github.com/github/github/pull/100507.
      options = [:UNSAFE, :GITHUB_PRE_LANG, :FULL_INFO_STRING, :FOOTNOTES]
      if context.fetch(:gfm, true)
        options << :HARDBREAKS
      end

      exts = EXTENSIONS
      if context[:skip_tagfilter]
        exts = exts.dup
        exts.delete(:tagfilter)
      end

      CommonMarker.render_html(text, options, exts).chomp
    end
  end
end
