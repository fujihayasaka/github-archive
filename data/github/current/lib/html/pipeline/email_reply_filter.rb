# typed: true
# frozen_string_literal: true
require "email_reply_parser"

module HTML
  class Pipeline
    # HTML Filter that converts email reply text into an HTML DocumentFragment.
    # It must be used as the first filter in a pipeline.
    #
    # Context options:
    #   None
    #
    # This filter does not write any additional information to the context hash.
    class EmailReplyFilter < TextFilter
      EMAIL_HIDDEN_HEADER    = %(<span class="email-hidden-toggle"><a href="#">&hellip;</a></span><div class="email-hidden-reply">).freeze
      EMAIL_QUOTED_HEADER    = %(<div class="email-quoted-reply">).freeze
      EMAIL_SIGNATURE_HEADER = %(<div class="email-signature-reply">).freeze
      EMAIL_FRAGMENT_HEADER  = %(<div class="email-fragment">).freeze
      EMAIL_HEADER_END       = "</div>".freeze
      # we capture a simplified email regex here to try and hide email
      # addresses. This won't capture every possible email address but the
      # simplified pattern of at least 2 characters (hence the two range
      # groups), where the first one is anything except @, whitespace, the dot
      # or the closing angle bracket (to not accidentally capture email quotes
      # followed by an @ for a user mention). The second one is anything
      # except the @ or whitespace zero or more times. The sequence needs to
      # be followed by an @ sign, and then an optional opening square bracket
      # (if a literal internet address is following), then at least one lower
      # case character, number, dot, or dash, followed again by an optional
      # closing square bracket.
      EMAIL_REGEX            = /[^@\s.>][^@\s]*@\[?[a-z0-9.-]+\]?/i
      HIDDEN_EMAIL_PATTERN   = "***@***.***"

      def self.cache_key(context)
        return unless context[:hide_quoted_email_addresses]
        "hide_quoted_email_addresses"
      end

      # Scans an email body to determine which bits are quoted and which should
      # be hidden. EmailReplyParser is used to split the comment into an Array
      # of quoted or unquoted Blocks. Now, we loop through them and attempt to
      # add <div> tags around them so we can hide the hidden blocks, and style
      # the quoted blocks differently. Since multiple blocks may be hidden, be
      # sure to keep the "email-hidden-reply" <div>s around "email-quoted-reply"
      # <div> tags. Call this on each comment of a visible thread in the order
      # that they are displayed. Note: all comments are processed so we can
      # maintain a Set of SHAs of paragraphs. Only plaintext comments skip the
      # markdown step.
      #
      # Returns the email comment HTML as a String
      def call
        found_hidden = T.let(nil, T.nilable(T::Boolean))
        paragraphs = EmailReplyParser.read(text.dup).fragments.map do |fragment|
          pieces = [ERB::Util.force_escape(fragment.to_s.strip).gsub(/^\s*(>|&gt;)/, "")]
          if fragment.quoted?
            if context[:hide_quoted_email_addresses]
              pieces.map! do |piece|
                piece.gsub(EMAIL_REGEX, HIDDEN_EMAIL_PATTERN)
              end
            end
            pieces.unshift EMAIL_QUOTED_HEADER
            pieces << EMAIL_HEADER_END
          elsif fragment.signature?
            pieces.unshift EMAIL_SIGNATURE_HEADER
            pieces << EMAIL_HEADER_END
          else
            pieces.unshift EMAIL_FRAGMENT_HEADER
            pieces << EMAIL_HEADER_END
          end
          if fragment.hidden? && !found_hidden
            found_hidden = true
            pieces.unshift EMAIL_HIDDEN_HEADER
          end
          pieces.join
        end
        paragraphs << EMAIL_HEADER_END if found_hidden
        paragraphs.join("\n")
      end
    end
  end
end
