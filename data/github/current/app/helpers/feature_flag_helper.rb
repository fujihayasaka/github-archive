# typed: true
# frozen_string_literal: true

module FeatureFlagHelper
  include Kernel

  def feature_enabled_for_current_user?(feature_name:, subject: nil)
    # Using `vexi.enabled` would make this function difficult to confirm that the previous behavior is preserved.
    if subject
      FeatureFlag.vexi.enabled_or_raise?(feature_name, subject) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    else
      FeatureFlag.vexi.enabled_or_raise?(feature_name, T.unsafe(self).current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end
  end

  def feature_enabled_globally_or_for_user?(feature_name:, subject: nil)
    FeatureFlag.vexi.enabled_or_raise?(feature_name) || feature_enabled_for_current_user?(feature_name: feature_name, subject: subject) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def client_side_feature_flags(app_specific_flags: [])
    return @client_side_feature_flags if defined? @client_side_feature_flags

    possible_flags = GitHubUI::FeatureFlags.js_flags

    FeatureFlag.vexi.preload(possible_flags, instrumentation_properties: {
      "code.namespace": "feature_flag_helper",
    })

    current_user_available = respond_to?(:current_user, true)
    actor = (GitHub.enterprise? || !current_user_available) ? nil : T.unsafe(self).current_user
    features = possible_flags.select do |flag|
      FeatureFlag.vexi.enabled_or_raise?(flag, actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    @client_side_feature_flags = features.map { |feature| feature.to_sym }
    @client_side_feature_flags += app_specific_flags
  end

  def css_feature_flags
    return @css_feature_flags if defined? @css_feature_flags

    possible_flags = GitHubUI::FeatureFlags.css_flags
    return if possible_flags.empty?

    FeatureFlag.vexi.preload(possible_flags, instrumentation_properties: {
      "code.namespace": "feature_flag_helper",
    })

    current_user_available = respond_to?(:current_user, true)
    actor = (GitHub.enterprise? || !current_user_available) ? nil : T.unsafe(self).current_user
    features = possible_flags.select do |flag|
      FeatureFlag.vexi.enabled_or_raise?(flag, actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    @css_feature_flags = features.map { |feature| feature.to_sym }
  end
end
