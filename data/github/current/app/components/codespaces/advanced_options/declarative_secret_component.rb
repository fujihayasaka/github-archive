# typed: true
# frozen_string_literal: true

class Codespaces::AdvancedOptions::DeclarativeSecretComponent < ApplicationComponent
  URL_HTTP_SCHEMES = %w(http https).freeze
  renders_one :field_tag

  def initialize(declared_secret)
    @declared_secret = declared_secret
  end

  def name
    @declared_secret[:name]
  end

  def description
    @declared_secret[:description]
  end

  memoize def documentation_url
    @declared_secret[:documentation_url] if safe_url?(@declared_secret[:documentation_url])
  end

  private

  def safe_url?(url)
    return false unless url && url.valid_encoding? && uri = Addressable::URI.parse(url)

    ::UrlHelper.valid_host?(uri.host) &&
      URL_HTTP_SCHEMES.include?(uri.scheme&.downcase) &&
      uri.userinfo.nil?
  end
end
