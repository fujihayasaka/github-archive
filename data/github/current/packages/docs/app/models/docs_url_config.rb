# typed: true
# frozen_string_literal: true

class DocsUrlConfig
  DOCS_URLS_CONFIG_PATH = ENV["DOCS_URLS_CONFIG_PATH"] || "config/docs-urls.json"

  class IdentifierError < RuntimeError; end
  class JSONConfigParseError < JSON::ParserError; end
  class JSONConfigFileError < Errno::ENOENT; end

  # Public: Return a full absolute URL to GitHub Docs for the given identifier.
  #
  # identifier - The identifier for the docs URL
  # ghec - Boolean whether the URL should start with /enterprise-cloud@latest
  # query - Hash of strings that becomes ?key=value&key2=value2
  # fragment - String that adds #fragment
  #
  # Examples:
  #
  #   DocsUrlConfig.url_for("auth/two-factor")
  #   # => "https://docs.github.com/authentication/about-two-factor-authentication"
  #
  #   url_for("auth/two-factor", ghec: true)
  #   # => "https://docs.github.com/enterprise-cloud@latest/authentication/about-two-factor-authentication"
  #
  #   url_for("auth/two-factor", query: {tool: "vscode"})
  #   # => "https://docs.github.com/authentication/about-two-factor-authentication?tool=vscode"
  #
  sig do
    params(
      identifier: String,
      ghec: T::Boolean,
      query: T::Hash[String, T.any(String, Integer)],
      fragment: String
    ).returns(String)
  end
  def self.url_for(identifier, ghec: false, query: {}, fragment: "")
    @docs_url_config ||= self.new
    @docs_url_config.url_for(identifier, ghec: ghec, query: query, fragment: fragment)
  end

  sig { params(config_file_path: String).void }
  def initialize(config_file_path = DOCS_URLS_CONFIG_PATH)
    @config_file_path = config_file_path
  end

  # Public: Return a full absolute URL to GitHub Docs for the given identifier.
  #
  # identifier - The identifier for the docs URL
  # ghec - Boolean whether the URL should start with /enterprise-cloud@latest
  # query - Hash of strings that becomes ?key=value&key2=value2
  # fragment - String that adds #fragment
  #
  # Examples:
  #
  #   url_for("auth/two-factor")
  #   # => "https://docs.github.com/authentication/about-two-factor-authentication"
  #
  #   url_for("auth/two-factor", ghec: true)
  #   # => "https://docs.github.com/enterprise-cloud@latest/authentication/about-two-factor-authentication"
  #
  #   url_for("auth/two-factor", query: {tool: "vscode"})
  #   # => "https://docs.github.com/authentication/about-two-factor-authentication?tool=vscode"
  #
  #   url_for("auth/two-factor", fragment: "å")
  #   # => "https://docs.github.com/authentication/about-two-factor-authentication#%C3%A5"
  #
  sig do
    params(
      identifier: String,
      ghec: T::Boolean,
      query: T::Hash[String, T.any(String, Integer)],
      fragment: String
    ).returns(String)
  end
  def url_for(identifier, ghec: false, query: {}, fragment: "")
    pathname = config[identifier]
    raise IdentifierError, "No such identifier: #{identifier}" if pathname.nil?
    uri = Addressable::URI.new(
      path: pathname,
      query_values: query.empty? ? nil : query,
      fragment: fragment.empty? ? nil : Addressable::URI.escape(fragment)
    )
    # We let the GitHub.help_url method take care of setting the prefix.
    # It will automatically use the `/enterprise-server@<RELEASE NUMBER>` of the GHES instance running,
    # but if the caller of this helper specifically wants the enterprise-cloud prefix, that will
    # be set and the enterprise-server prefix will not be used.
    "#{GitHub.help_url(skip_enterprise: ghec, ghec_exclusive: ghec)}#{uri}"
  end

  private

  sig { returns T::Hash[String, String] }
  def config
    @loaded ||= load_config
  end

  sig { returns T::Hash[String, String] }
  def load_config
    JSON.parse(File.read(Rails.root.join(@config_file_path)))
  rescue JSON::ParserError => e
    raise JSONConfigParseError.new(e)
  rescue Errno::ENOENT => e
    raise JSONConfigFileError.new(e.to_s)
  end
end
