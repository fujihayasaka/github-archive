# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Owner
  # Owner level enablement for CustomPatterns
  class CustomPatterns
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(owner: T.any(Organization, Business, Repository, User)).void }
    def initialize(owner)
      @owner = owner
      @custom_patterns = T.let(
        if @owner.is_a?(Business)
          SecretScanning::Features::Business::CustomPatterns.new(@owner)
        elsif @owner.is_a?(Organization)
          SecretScanning::Features::Org::CustomPatterns.new(@owner)
        elsif @owner.is_a?(Repository)
          SecretScanning::Features::Repo::CustomPatterns.new(@owner)
        else
          SecretScanning::Features::User::CustomPatterns.new(@owner)
        end, T.any(SecretScanning::Features::Business::CustomPatterns, SecretScanning::Features::Org::CustomPatterns, SecretScanning::Features::Repo::CustomPatterns, SecretScanning::Features::User::CustomPatterns))
    end

    delegate :feature_available?, to: :@custom_patterns
  end
end
