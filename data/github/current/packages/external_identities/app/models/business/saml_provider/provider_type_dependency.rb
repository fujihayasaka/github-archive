# typed: false
# frozen_string_literal: true

module Business::SamlProvider::ProviderTypeDependency
  PROVIDER_TYPE_REGEX = {
    # https://rubular.com/r/SmEJtKYKcFd6UC
    /sts\.(windows|windows\-ppe)\.net/i => :azure_ad,

    # https://rubular.com/r/AEmI0myyg95kgm
    /www\.okta\.com/i => :okta
  }

  def find_provider_type
    pattern = PROVIDER_TYPE_REGEX.keys.find { |pattern| pattern.match(issuer) }
    PROVIDER_TYPE_REGEX[pattern] || :unknown
  end

  def self.find_provider_type_from_issuer(issuer)
    pattern = PROVIDER_TYPE_REGEX.keys.find { |pattern| pattern.match(issuer) }
    PROVIDER_TYPE_REGEX[pattern] || :unknown
  end
end
