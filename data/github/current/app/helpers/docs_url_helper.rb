# typed: true
# frozen_string_literal: true

# Public: Used for making links to GitHub Docs from ERB files.
module DocsUrlHelper
  extend T::Sig

  # Public: Return a full absolute URL to GitHub Docs for the given identifier.
  #
  # identifier - The String identifier for the docs page/
  # ghec - Boolean whether the URL should start with /enterprise-cloud@latest
  # query - Hash of strings that becomes ?key=value&key2=value2
  # fragment - String that adds #fragment
  #
  # Examples:
  #
  #   docs_url("auth/two-factor")
  #   # => "https://docs.github.com/authentication/about-two-factor-authentication"
  #
  sig do
    params(
      identifier: String,
      ghec: T::Boolean,
      query: T::Hash[String, T.any(String, Integer)],
      fragment: String
    ).returns(String)
  end
  def docs_url(identifier, ghec: false, query: {}, fragment: "")
    DocsUrlConfig.url_for(identifier, ghec: ghec, query: query, fragment: fragment)
  end
end
