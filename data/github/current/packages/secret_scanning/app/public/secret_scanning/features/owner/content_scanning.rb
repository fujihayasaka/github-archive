# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Owner
  # Owner level enablement for Issue Scanning
  class ContentScanning
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @issue_scanning = T.let(if @owner.is_a?(Business)
                                SecretScanning::Features::Business::ContentScanning.new(@owner)
                              elsif @owner.is_a?(Organization)
                                SecretScanning::Features::Org::ContentScanning.new(@owner)
                              else
                                SecretScanning::Features::User::ContentScanning.new(@owner)
                              end, T.any(SecretScanning::Features::Business::ContentScanning, SecretScanning::Features::Org::ContentScanning, SecretScanning::Features::User::ContentScanning))
    end

    delegate :feature_available?,
    :enabled?,
    :scan_all_token_types_enabled?,
    to: :@issue_scanning
  end
end
