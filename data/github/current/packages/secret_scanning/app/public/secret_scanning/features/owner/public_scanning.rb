# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Owner
  # Public Scanning feature
  #
  class PublicScanning
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @public_scanning = T.let(
        if @owner.is_a?(Business)
          SecretScanning::Features::Business::PublicScanning.new(@owner)
        elsif @owner.is_a?(Organization)
          SecretScanning::Features::Org::PublicScanning.new(@owner)
        else
          SecretScanning::Features::User::PublicScanning.new(@owner)
        end,
        T.any(SecretScanning::Features::Business::PublicScanning, SecretScanning::Features::Org::PublicScanning, SecretScanning::Features::User::PublicScanning))
    end

    delegate :feature_available?,
    :can_enable_for_new_repos?,
    :secret_scanning_enabled_for_new_repos?,
    to: :@public_scanning
  end
end
