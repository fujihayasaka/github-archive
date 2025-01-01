# typed: true
# frozen_string_literal: true

module Commits
  module CommitMessageable
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { abstract.returns(String) }
    def message; end

    sig { abstract.returns(String) }
    def oid; end

    sig { abstract.returns(Repository) }
    def repository; end

    sig { abstract.returns(T.class_of(Class)) }
    def class; end

    # Public: The CommitMessage (plain text) object.
    def message_text
      @message_text ||= Commits::CommitMessage.new(message)
    end

    # Public: The (possibly truncated) commit short message as plain text.
    def short_message_text
      message_text.subject
    end

    # Public: The longer (possibly truncated) commit short message as plain text.
    def longer_short_message_text
      message_text.longer_subject
    end

    # Public: The body part of the plain text message. This is anything
    # following the first line feed. Leading and trailing whitespace is
    # stripped.
    def message_body_text
      message_text.body
    end

    # Public: Is there a long part?
    def message_body_text?
      message_body_text && !message_body_text.empty?
    end

    # Public: A CommitMessageHTML object, useful for formatting commit message subject
    # and body with support for truncation and splitting.
    def message_html
      @message_html ||=
        Commits::CommitMessageHTML.new(message, message_context)
    end

    # Public: Truncated HTML of the commit's short message.
    #
    # Returns the short message HTML as a String. No wrapping element is
    # included, although various inline markup may be present.
    def short_message_html
      async_short_message_html.sync
    end

    def async_short_message_html
      return @async_short_message_html if defined?(@async_short_message_html)

      subject_promise = Platform::Loaders::Cache.fetch(message_cache_key("short_message_html")) do
        message_html.async_subject
      end

      @async_short_message_html = subject_promise.then(&:html_safe)
    end

    # Public: Longer truncated HTML of the commit's short message.
    #
    # Returns the short message HTML as a String. No wrapping element is
    # included, although various inline markup may be present.
    def longer_short_message_html
      async_longer_short_message_html.sync
    end

    def async_longer_short_message_html
      return @async_longer_short_message_html if defined?(@async_longer_short_message_html)

      subject_promise = Platform::Loaders::Cache.fetch(message_cache_key("longer_short_message_html")) do
        message_html.async_longer_subject
      end

      @async_longer_short_message_html = subject_promise.then(&:html_safe)
    end

    # Public: HTML version of the commit's body message.
    #
    # Returns the body message HTML as a String. No wrapping element is
    # included, although various inline markup may be present. The string will
    # be empty when no body is present, nil is never returned.
    def message_body_html
      async_message_body_html.sync
    end

    def async_message_body_html
      return @async_message_body_html if defined?(@async_message_body_html)

      body_promise = Platform::Loaders::Cache.fetch(message_cache_key("message_body_html")) do
        message_html.async_body
      end

      @async_message_body_html = body_promise.then(&:html_safe)
    end

    # Public: HTML version of the commit's body message.
    #
    # Returns the body message HTML as a String. No wrapping element is
    # included, although various inline markup may be present. The string will
    # be empty when no body is present, nil is never returned.
    def message_body_html_longer_subject
      async_message_body_html_longer_subject.sync
    end

    def async_message_body_html_longer_subject
      return @async_message_body_html_longer_subject if defined?(@async_message_body_html_longer_subject)

      body_promise = Platform::Loaders::Cache.fetch(message_cache_key("message_body_html_no_subject")) do
        message_html.async_longer_body
      end

      @async_message_body_html_longer_subject = body_promise.then { |body| body ? body.html_safe : "" } # rubocop: disable Rails/OutputSafety
    end

    # Public: Truncated HTML version of the commit's body message.
    #
    # limit - The maximum number of _visibly rendered_ characters allowed.
    #
    # Returns the body message HTML as a String. No wrapping element is
    # included, although various inline markup may be present. The string will
    # be empty when no body is present, nil is never returned.
    def async_truncated_message_body_html(limit)
      async_message_body_html.then do |body_html|
        HTMLTruncator.new(body_html, limit).to_html
      end
    end

    # Does the commit message include an extended body? This can happen when a
    # long message is given OR when a commit message subject is truncated and
    # spills over.
    def message_body_html?
      message_html.body?
    end

    # The HTML Pipeline context hash used when turning commit messages into HTML.
    def message_context
      @message_context ||= {
        entity: repository,
        base_url: GitHub.url,
        asset_proxy: GitHub.image_proxy_url,
        disable_asset_proxy: !GitHub.image_proxy_enabled?,
        whitelist: nil,
        location: self.class.name,
      }
    end

    # The BodyContent object with the fully processed HTML message and resulting
    # context items.
    #
    # Returns a GitHub::HTML::BodyContent object.
    def message_content
      @message_content ||=
        GitHub::HTML::BodyContent.new(message, message_context, GitHub::Goomba::CommitMessagePipeline)
    end

    # The GitHub::HTML Result object.
    def message_result
      message_content.result
    end

    # Generate a message_cache key for memcached.
    def message_cache_key(attribute)
      repo_key = repository.name_with_owner

      [
        "commit-message",
        "v10",
        attribute,
        repo_key,
        oid,
        KeyLinks::Public.key_links_cache_key_for(repository)
      ].compact.join(":")
    end
  end
end
