# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "hashids"

module Codespaces
  HASHID_SALT = "c0d3sp4c3s are the best"
  CODE_TAB_NOTICE_NAME = "codespaces_code_tab"
  CODE_TAB_INDIVIDUALS_NOTICE_NAME = "codespaces_code_tab_individuals"
  MAX_CODESPACES_PAGE_SIZE = 50
  MAX_SESSION_TIME = 12.hours

  def self.trusted_repository_authorizations_with_repository(user)
    user.trusted_repository_authorizations.reject { |trusted_repository_authorization| trusted_repository_authorization.repository.nil? }
  end

  def self.repository_authorizations(user)
    user.codespaces_repository_authorizations.reject { |repository_authorization| repository_authorization.repository.nil? }
  end

  def self.hashid
    # Limit (offensive) word generation in suffix
    # Context: https://github.com/github/codespaces/issues/735
    # and https://github.com/google/open-location-code/blob/master/docs/olc_definition.adoc#open-location-code
    @hashid ||= Hashids.new(HASHID_SALT, 0, "23456789cfghjmpqrvwx")
  end

  def self.monolith_url_builder
    @url_builder ||= GitHub::UrlBuilder.new(host_name: GitHub.codespaces_monolith_host_name, no_api_prefix_with_suffix: true)
  end
end
