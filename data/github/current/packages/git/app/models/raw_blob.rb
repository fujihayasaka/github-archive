# typed: false
# frozen_string_literal: true

class RawBlob
  module ContentHelpers
    def mime_for(path)
      GitHub::MimeTypeHelpers.simplified(MiniMime.lookup_by_filename(path.to_s)) || DEFAULT_MIME
    end

    def raw_mime_for(path, is_text: nil)
      raw_mime(mime_for(path), is_text: is_text)
    end

    def raw_mime(mime, is_text: nil)
      RawBlob.raw_mime(mime, is_text: is_text)
    end
  end

  module AbstractRepositoryHelper
    include GitHub::UTF8

    def self.included(base)
      super
      if base.respond_to?(:helper_method)
        base.helper_method :raw_domain_token
      end
    end

    def tree_name_for_display
      utf8(tree_name.dup)
    end

    def raw_domain_token(expires_key, options = {})
      return unless needs_a_token? && user_session
      RawBlob.token(current_repository, raw_token_scope(options), expires_key, session: user_session)
    end

    def raw_token_scope(options = {})
      return unless current_repository
      options[:name] ||= params[:name]
      RawBlob.scope(current_repository, options[:name], prepare_path(options))
    end

    def raw_wiki_domain_token(expires_key, options = {})
      return unless needs_a_token? && user_session
      RawBlob.token(current_repository, raw_wiki_token_scope(options), expires_key, session: user_session)
    end

    def raw_wiki_token_scope(options = {})
      return unless current_repository
      RawBlob.wiki_scope(current_repository, prepare_path(options))
    end

    private

    def needs_a_token?
      (current_repository && current_repository.private?) ||
        (GitHub.enterprise? && GitHub.private_mode_enabled?)
    end

    def prepare_path(options)
      path = options[:path] || params[:path]
      path = Array(path).join("/")
      path
    end
  end

  DEFAULT_MIME = "application/octet-stream"
  TEXT_MIME = "text/plain"
  TEXT_PREFIXES = %w(text/)
  TEXT_SUFFIXES = %w(+svg +json +xml)
  BINARY_PREFIXES = %w(audio/ video/ image/)

  BINARY_MIMES = Set.new %w(
    application/zip
    application/x-gzip
    image/svg+xml
  )

  EXPIRES = {
    blob: 1.week,
    render: 60.seconds,
  }

  # Normalizes the given mime type to an approved mime type for displaying
  # raw binary files on GitHub.
  #
  # input   - String mime type.
  # is_text - Optional boolean specifying that the file is a text file.  Usually
  #           guessed by something like Linguist.
  #
  # Returns a String mime type.
  def self.raw_mime(input, is_text: nil)
    mime = input.to_s.downcase
    ctype, extra = mime.split(";", 2)

    if BINARY_MIMES.include?(ctype)
      return input
    end

    if is_text == true || TEXT_PREFIXES.any? { |p| mime.start_with?(p) } || TEXT_SUFFIXES.any? { |s| ctype.end_with?(s) }
      if extra.present?
        return "#{TEXT_MIME};#{extra}"
      else
        return TEXT_MIME
      end
    end

    if BINARY_PREFIXES.any? { |p| mime.start_with?(p) }
      return input
    end

    DEFAULT_MIME
  end

  # Public: Builds an expiring token for the user to access the repository.
  #
  # repository - The Repository.
  # scope      - The String scope for the token.  See #scope.
  # expires    - A Symbol key for the expires configuration.
  # user       - The User with read access to the repository.
  # session    - The Session of the current user.
  #
  # Returns a String token or nil if no token is necessary.
  def self.token(repository, scope, expires, session: nil, user: nil)
    # Note: Only one of User or Session may be provided. Providing both (or neither) will raise an ArgumentError in the call below.
    duration = EXPIRES.fetch(expires) do
      raise ArgumentError, "Unknown expires: #{expires.inspect}"
    end

    if expires == :blob && repository.is_a?(Repository)
      duration = repository.plan_limit(:raw_blob_access_expires_in_seconds).seconds
    end

    if user&.bot? && user.installation.present?
      data = { installation_id: user.installation.id, installation_type: user.installation.class.to_s }
    end

    GitHub::Authentication::SignedAuthToken.generate(user: user, session: session, scope: scope, expires: duration.from_now, data: data)
  end

  # Public: Builds a token scope for the given path.
  #
  # repository - The Repository.
  # tree_name  - The String tree name (a branch, tag, or commit).
  # path       - The String path to the file, with no leading slash.
  #
  # Returns a String scope to use to build a token.
  def self.scope(repository, tree_name, path)
    tree_name, path = tree_name.dup, path.dup

    tree_name.force_encoding("UTF-8").scrub! unless tree_name.blank?
    path.force_encoding("UTF-8").scrub! unless path.blank?
    "RawBlob:#{repository.token_scope}/#{tree_name}/#{path}"
  end

  # Public: Builds a token scope for the given wiki path.
  #
  # repository - The Repository.
  # path       - The String path to the file, with no leading slash.
  #
  # Returns a String scope to use to build a token.
  def self.wiki_scope(repository, path)
    "Wiki:#{repository.token_scope}/#{path}"
  end

  # Public: Builds a token scope for the given gist file
  #
  # repository - The Gist.
  # path       - The String path to the file, with no leading slash.
  #
  # Returns a String scope to use to build a token.
  def self.gist_scope(gist, commit_oid, path)
    "Gist:#{gist.name_with_owner}/#{commit_oid}/#{path}"
  end

  # Public: Calculates the max age for caching purposes.
  #
  # verify - A GitHub::Authentication::SignedAuthToken object.
  #
  # Returns the Integer max age in seconds.
  def self.max_age_from(verify, fallback: 1.hour)
    if expires = verify.try(:expires)
      if (expires - Time.now) <= 60
        return 60
      end
    end

    fallback.to_i
  end
end
