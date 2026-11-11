# typed: true
# frozen_string_literal: true

module Commits
  module CommitMessageable
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

    # Public: Is the commit message subject truncated?
    def truncated?
      message_text.truncated?
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
    sig { params(viewer: T.nilable(Users::IUser)).returns(Commits::CommitMessageHTML) }
    def message_html(viewer: nil)
      context = viewer ? message_context.merge(current_user: viewer) : message_context
      @message_html_by_viewer ||= {}
      @message_html_by_viewer[viewer&.id] ||= Commits::CommitMessageHTML.new(message, context)
    end

    # Public: Truncated HTML of the commit's short message.
    #
    # Returns the short message HTML as a String. No wrapping element is
    # included, although various inline markup may be present.
    sig { params(viewer: T.nilable(Users::IUser)).returns(String) }
    def short_message_html(viewer: nil)
      async_short_message_html(viewer: viewer).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(Promise[String]) }
    def async_short_message_html(viewer: nil)
      @async_short_message_html_by_viewer ||= {}
      return @async_short_message_html_by_viewer[viewer&.id] if @async_short_message_html_by_viewer.key?(viewer&.id)

      subject_promise = Platform::Loaders::Cache.fetch(message_cache_key("short_message_html", viewer: viewer)) do
        message_html(viewer: viewer).async_subject
      end

      @async_short_message_html_by_viewer[viewer&.id] = subject_promise.then(&:html_safe)
    end

    # Public: Longer truncated HTML of the commit's short message.
    #
    # Returns the short message HTML as a String. No wrapping element is
    # included, although various inline markup may be present.
    sig { params(viewer: T.nilable(Users::IUser)).returns(String) }
    def longer_short_message_html(viewer: nil)
      async_longer_short_message_html(viewer: viewer).sync
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(Promise[String]) }
    def async_longer_short_message_html(viewer: nil)
      @async_longer_short_message_html_by_viewer ||= {}
      return @async_longer_short_message_html_by_viewer[viewer&.id] if @async_longer_short_message_html_by_viewer.key?(viewer&.id)

      subject_promise = Platform::Loaders::Cache.fetch(message_cache_key("longer_short_message_html", viewer: viewer)) do
        message_html(viewer: viewer).async_longer_subject
      end

      @async_longer_short_message_html_by_viewer[viewer&.id] = subject_promise.then(&:html_safe)
    end

    # Public: HTML version of the commit's body message.
    #
    # Returns the body message HTML as a String. No wrapping element is
    # included, although various inline markup may be present. The string will
    # be empty when no body is present, nil is never returned.
    sig { params(viewer: T.nilable(Users::IUser)).returns(String) }
    def message_body_html(viewer: nil)
      async_message_body_html(viewer: viewer).sync
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(Promise[String]) }
    def async_message_body_html(viewer: nil)
      @async_message_body_html_by_viewer ||= {}
      return @async_message_body_html_by_viewer[viewer&.id] if @async_message_body_html_by_viewer.key?(viewer&.id)

      body_promise = Platform::Loaders::Cache.fetch(message_cache_key("message_body_html", viewer: viewer)) do
        message_html(viewer: viewer).async_body
      end

      @async_message_body_html_by_viewer[viewer&.id] = body_promise.then(&:html_safe)
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(String) }
    def full_subject_html(viewer: nil)
      async_full_subject_html(viewer: viewer).sync
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(Promise[String]) }
    def async_full_subject_html(viewer: nil)
      @async_full_subject_html_by_viewer ||= {}
      return @async_full_subject_html_by_viewer[viewer&.id] if @async_full_subject_html_by_viewer.key?(viewer&.id)

      subject_promise = Platform::Loaders::Cache.fetch(message_cache_key("message_full_subject_html", viewer: viewer)) do
        message_html(viewer: viewer).async_full_subject_html
      end

      @async_full_subject_html_by_viewer[viewer&.id] = subject_promise.then(&:html_safe)
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(String) }
    def full_body_html(viewer: nil)
      async_full_body_html(viewer: viewer).sync
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(Promise[String]) }
    def async_full_body_html(viewer: nil)
      @async_full_body_html_by_viewer ||= {}
      return @async_full_body_html_by_viewer[viewer&.id] if @async_full_body_html_by_viewer.key?(viewer&.id)

      body_promise = Platform::Loaders::Cache.fetch(message_cache_key("message_full_body_html", viewer: viewer)) do
        message_html(viewer: viewer).async_body_html
      end

      @async_full_body_html_by_viewer[viewer&.id] = body_promise.then { |body| body ? body.html_safe : "" } # rubocop: disable Rails/OutputSafety
    end

    # Public: HTML version of the commit's body message.
    #
    # Returns the body message HTML as a String. No wrapping element is
    # included, although various inline markup may be present. The string will
    # be empty when no body is present, nil is never returned.
    sig { params(viewer: T.nilable(Users::IUser)).returns(String) }
    def message_body_html_longer_subject(viewer: nil)
      async_message_body_html_longer_subject(viewer: viewer).sync
    end

    sig { params(viewer: T.nilable(Users::IUser)).returns(Promise[String]) }
    def async_message_body_html_longer_subject(viewer: nil)
      @async_message_body_html_longer_subject_by_viewer ||= {}
      return @async_message_body_html_longer_subject_by_viewer[viewer&.id] if @async_message_body_html_longer_subject_by_viewer.key?(viewer&.id)

      body_promise = Platform::Loaders::Cache.fetch(message_cache_key("message_body_html_no_subject", viewer: viewer)) do
        message_html(viewer: viewer).async_longer_body
      end

      @async_message_body_html_longer_subject_by_viewer[viewer&.id] = body_promise.then { |body| body ? body.html_safe : "" } # rubocop: disable Rails/OutputSafety
    end

    # Public: Truncated HTML version of the commit's body message.
    #
    # limit - The maximum number of _visibly rendered_ characters allowed.
    #
    # Returns the body message HTML as a String. No wrapping element is
    # included, although various inline markup may be present. The string will
    # be empty when no body is present, nil is never returned.
    sig { params(limit: Integer, viewer: T.nilable(Users::IUser)).returns(Promise[String]) }
    def async_truncated_message_body_html(limit, viewer: nil)
      async_message_body_html(viewer: viewer).then do |body_html|
        HTMLTruncator.new(body_html, limit).to_html
      end
    end

    # Does the commit message include an extended body? This can happen when a
    # long message is given OR when a commit message subject is truncated and
    # spills over.
    sig { params(viewer: T.nilable(Users::IUser)).returns(T::Boolean) }
    def message_body_html?(viewer: nil)
      message_html(viewer: viewer).body?
    end

    # The HTML Pipeline context hash used when turning commit messages into HTML.
    sig { overridable.returns(Hash) }
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
    sig { params(viewer: T.nilable(Users::IUser)).returns(GitHub::HTML::BodyContent) }
    def message_content(viewer: nil)
      context = viewer ? message_context.merge(current_user: viewer) : message_context
      @message_content_by_viewer ||= {}
      @message_content_by_viewer[viewer&.id] ||= GitHub::HTML::BodyContent.new(message, context, GitHub::Goomba::CommitMessagePipeline)
    end

    # The GitHub::HTML Result object.
    def message_result(viewer: nil)
      message_content(viewer: viewer).result
    end

    # Generate a message_cache key for memcached.
    sig { params(attribute: String, viewer: T.nilable(Users::IUser)).returns(String) }
    def message_cache_key(attribute, viewer: nil)
      repo_key = repository.name_with_owner

      key = Repositories.domain.key_links.cache_key(T.must(repository.id))

      [
        "commit-message",
        "v11",
        attribute,
        repo_key,
        oid,
        key,
        viewer&.display_login
      ].compact.join(":")
    end
  end
end
