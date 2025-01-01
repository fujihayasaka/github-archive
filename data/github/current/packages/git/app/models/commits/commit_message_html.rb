# typed: true
# frozen_string_literal: true

module Commits
  # Like CommitMessage but generates HTML output instead of plain text. The
  # logic for this is very different since the text displayed in an HTML commit
  # messages may be shortened considerably compared to the messages plain text.
  # For instance, the CommitMention filter replaces 40 char SHA1s with 7 char
  # SHA1s with links. We want to truncate based on the *visible* HTML text, not
  # the original text or the HTML markup.
  class CommitMessageHTML < CommitMessage
    include ActionView::Helpers::OutputSafetyHelper

    LONG_COMMIT_MESSAGE = 51_200

    # Create a new CommitMessage with the text message provided. This should be
    # the full commit message.
    #
    # message - The full plain text commit message as a String.
    # context - The HTML pipeline context hash.
    def initialize(message, context = {}, pipeline = GitHub::Goomba::CommitMessagePipeline)
      @message, @subject, @body_text = split_message(message)
      @context = context
      @context[:location] = Commit.name
      @pipeline = pipeline
      @subject_pipeline = pipeline
      prevent_url_subject_from_being_link
    end

    # The original commit message string without modifications.
    attr_reader :message

    # Does the commit message have a body? True when the subject is truncated
    # and spills over into the body as well as when a proper body is present.
    def body?
      return true if @body_text
      truncated?
    end

    def prevent_url_subject_from_being_link
      @subject_pipeline = GitHub::Goomba::CommitSubjectPipeline if subject_is_url?
    end

    SUBJECT_IS_URL_REGEX = /\A\s*#{URI::DEFAULT_PARSER.make_regexp(%w(http https))}\s*\z/
    def subject_is_url?
      SUBJECT_IS_URL_REGEX.match?(@subject)
    end

    # The body of the commit message, possibly including the removed portion of
    # the message subject.
    #
    # Returns a String of HTML markup or nil when no body is present.
    def async_body
      return @async_body if defined?(@async_body)

      @async_body = Promise.all([async_subject_overflow, async_body_html]).then do |overflow, body_html|
        next "" if overflow.nil? && body_html.nil?
        [overflow, body_html].compact.join("\n\n").rstrip.html_safe # rubocop: disable Rails/OutputSafety
      end
    end

    def body
      async_body.sync
    end

    # The longer body of the commit message, possibly including the removed portion of
    # the message subject.
    #
    # Returns a String of HTML markup or nil when no body is present.
    def async_longer_body
      return @async_longer_body if defined?(@async_longer_body)

      @async_longer_body = Promise.all([async_longer_subject_overflow, async_body_html]).then do |overflow, body_html|
        next "" if overflow.nil? && body_html.nil?
        [overflow, body_html].compact.join("\n\n").rstrip.html_safe # rubocop: disable Rails/OutputSafety
      end
    end

    def longer_body
      async_longer_body.sync
    end

    # The (possibly truncated) subject as a String of HTML markup.
    def async_subject
      return @async_subject if defined?(@async_subject)
      @async_subject = async_split_subject.then(&:first).then(&:html_safe)
    end

    # The (possibly truncated) subject as a String of HTML markup.
    def async_longer_subject
      return @async_longer_subject if defined?(@async_longer_subject)
      @async_longer_subject = async_longer_split_subject.then(&:first).then(&:html_safe)
    end

    def subject
      async_subject.sync
    end

    def async_truncated?
      async_split_subject.then { |_, overflow| !overflow.nil? }
    end

    def truncated?
      async_truncated?.sync
    end

    # The subject and body as a single HTML string.
    def to_html
      safe_join([subject, body].compact, "\n\n")
    end
    alias to_s to_html

    ##
    # Internal Methods

    # Determine if the subject overflows the maximum length and move excess to
    # the body if so.
    def async_split_subject
      return @async_split_subject if defined?(@async_split_subject)

      @async_split_subject = async_subject_document.then do |doc|
        truncator = HTMLTruncator.new(doc, Commits::CommitMessage::MAX)
        subject = truncator.to_html(wrap: false)
        if node = truncator.remaining.child
          subject_overflow = node.inner_html.strip
          subject_overflow = nil if subject_overflow.empty?
          [subject, subject_overflow]
        else
          [subject, nil]
        end
      end
    end

    # Determine if the subject overflows the maximum length of 200 and move excess to
    # the body if so.
    def async_longer_split_subject
      return @async_longer_split_subject if defined?(@async_longer_split_subject)

      @async_longer_split_subject = async_subject_document.then do |doc|
        truncator = HTMLTruncator.new(doc, Commits::CommitMessage::LONG_MESSAGE_SUBJECT_MAX_LENGTH)
        subject = truncator.to_html(wrap: false)
        if node = truncator.remaining.child
          subject_overflow = node.inner_html.strip
          subject_overflow = nil if subject_overflow.empty?
          [subject, subject_overflow]
        else
          [subject, nil]
        end
      end
    end

    def async_full_subject_html
      return @async_full_subject_html if defined?(@async_full_subject_html)

      @async_full_subject_html = async_subject_document.then do |doc|
        doc.to_html(wrap: false)
      end
    end

    def async_subject_document
      return @async_subject_document if defined?(@async_subject_document)

      body_content = GitHub::HTML::BodyContent.new(@subject, @context, @subject_pipeline)
      @async_subject_document = body_content.async_document
    end

    def async_body_html
      return @async_body_html if defined?(@async_body_html)

      return @async_body_html = Promise.resolve(nil) if @body_text.nil?

      @async_body_html = commit_message_pipeline.async_to_html(@body_text, @context).then do |body|
        body[0, 5] == "<div>" ? body[5...-6] : body # remove <div></div> wrapper
      end
    end

    # Run the body text through the HTML pipeline to linkify and otherwise
    # format. Returns nil with no body.
    def body_html
      async_body_html.sync
    end

    # HTML pipeline used to process the message. When the commit message is
    # excessively large (>50K) only basic plain text formatting is applied.
    def commit_message_pipeline
      if @message.length > LONG_COMMIT_MESSAGE
        GitHub::Goomba::LongCommitMessagePipeline
      else
        @pipeline
      end
    end

    def async_subject_overflow
      async_split_subject.then(&:last)
    end

    def async_longer_subject_overflow
      async_longer_split_subject.then(&:last)
    end
  end
end
