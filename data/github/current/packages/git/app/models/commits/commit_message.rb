# typed: true
# frozen_string_literal: true

module Commits
  # Commit message formatting class. Takes commit messages of all shapes and
  # sizes and ensures a sane subject and body. When the subject exceeds 72
  # characters, it's truncated and the removed portion is moved to the body.
  #
  # This class handles plain text commit messages only and should not be used
  # when the commit message is to be displayed as HTML. Use the
  # CommitMessageHTML class instead.
  class CommitMessage
    include GitHub::UTF8

    ELLIPSIS = "…"
    MAX = 72
    LONG_MESSAGE_SUBJECT_MAX_LENGTH = 200
    # We always truncate at least 3 characters off the end to avoid creating a
    # body that is just an ellipsis followed by one or two characters (which
    # looks silly).
    TRUNCATED_LENGTH = MAX - 3
    LONGER_SUBJECT_TRUNCATED_LENGTH = LONG_MESSAGE_SUBJECT_MAX_LENGTH - 3

    # Create a new CommitMessage with the text message provided. This should be
    # the full commit message.
    def initialize(message)
      @message, @subject, @body = split_message(message)
      @tooltip = @message.rstrip

      if @subject.length > LONG_MESSAGE_SUBJECT_MAX_LENGTH
        @longer_subject = "#{@subject[0, LONGER_SUBJECT_TRUNCATED_LENGTH]}#{ELLIPSIS}"
      else
        @longer_subject = @subject
      end

      if @subject.length > MAX
        @truncated = true
        body_part = "#{ELLIPSIS}#{subject[TRUNCATED_LENGTH..-1]}".rstrip
        @subject = "#{@subject[0, TRUNCATED_LENGTH]}#{ELLIPSIS}"
        @body = [body_part, @body].compact.join("\n\n")
      end
    end

    # The original commit message string without modifications.
    attr_reader :message

    # The commit message string used as title for truncated commit messages.
    attr_reader :tooltip

    # The (possibly truncated) subject of the commit message. This is the first
    # line or the first 69 characters with an ellipsis.
    attr_reader :subject

    # The (possibly truncated) subject of the commit message. This is the first
    # line or the first 197 characters with an ellipsis.
    attr_reader :longer_subject

    # The body part of the message. If the subject was truncated, this will
    # included the removed portion of the subject as well.
    attr_reader :body

    # Does the commit message have a body?
    def body?
      !@body.nil?
    end

    # Was the subject truncated due to being over 72 chars?
    def truncated?
      @truncated
    end

    # The subject and body as a String separated by two lines.
    def to_s
      if @body
        [@subject, @body].join("\n\n")
      else
        @subject
      end
    end

    alias_method :to_str, :to_s

    private

    def split_message(message)
      message = utf8(message.to_s)
      subject, body = message.split(/\n+/, 2)
      if subject
        subject.rstrip!
        subject = strip_spammy_unicode_from(subject)
      end

      if body
        body.rstrip!
        body = strip_spammy_unicode_from(body)
        body = nil if body.empty?
      end

      [message, subject.to_s, body]
    end

    def strip_spammy_unicode_from(input)
      input.gsub(/\p{M}{4,}/, "")
    end
  end
end
