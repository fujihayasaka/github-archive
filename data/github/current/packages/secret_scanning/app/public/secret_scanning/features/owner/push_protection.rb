# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Owner
  # Owner level enablement for Push Protection
  class PushProtection
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @push_protection = if @owner.is_a?(Business)
        SecretScanning::Features::Business::PushProtection.new(@owner)
      elsif @owner.organization?
        SecretScanning::Features::Org::PushProtection.new(@owner)
      else
        SecretScanning::Features::User::PushProtection.new(@owner)
      end
    end

    delegate  :feature_available?,
              :enabled_for_new_repos?,
              :custom_message_enabled?,
              :custom_message_active,
              :enable_custom_message,
              :disable_custom_message,
              :enable_for_new_repos,
              :disable_for_new_repos,
              to: :@push_protection
  end
end
