# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Wiki Scanning
  class WikiScanning
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @public_scanning = T.let(SecretScanning::Features::Repo::PublicScanning.new(@repo), SecretScanning::Features::Repo::PublicScanning)
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless GitHub.secret_scanning_for_all_content_types_enabled?
      return false unless self.wiki_exists_in_spokes?

      # feature is available on public repos if public scanning is enabled, or if token scanning is enabled
      @public_scanning.enabled? || @token_scanning.enabled?
    end

    sig { returns(T::Boolean) }
    def enabled?
      self.feature_available?
    end

    # Check whether the git repo behind the wiki exists in spokes
    sig { returns(T::Boolean) }
    def wiki_exists_in_spokes?
      wiki = @repo.unsullied_wiki
      return false if wiki.nil?
      wiki.exist?
    end
  end
end
