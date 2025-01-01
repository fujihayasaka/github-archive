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

  def feature_enabled_for_current_visitor?(feature_name:)
    return false unless T.unsafe(self).current_visitor
    result = FeatureFlag.vexi.enabled(feature_name, User::CurrentVisitorActor.from_current_visitor(T.unsafe(self).current_visitor.octolytics_id), default: false)
    raise result.error if result.error # preserve previous error handling behavior
    result.value
  end

  def feature_enabled_globally_or_for_user?(feature_name:, subject: nil)
    result = FeatureFlag.vexi.enabled(feature_name, default: false)
    raise result.error if result.error # preserve previous error handling behavior
    result.value || feature_enabled_for_current_user?(feature_name: feature_name, subject: subject)
  end

  def feature_enabled_globally_or_for_visitor?(feature_name:)
    result = FeatureFlag.vexi.enabled(feature_name, default: false)
    raise result.error if result.error # preserve previous error handling behavior
    result.value || (respond_to?(:current_visitor, true) && feature_enabled_for_current_visitor?(feature_name: feature_name))
  end

  def features_datafile_tag
    T.bind(self, ApplicationHelper)
    return if datafile_features.blank?
    features = FlipperFeature.where(name: datafile_features) # rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage

    datafile = {
      features: features.map do |feature|
        {
          name: feature.name,
          enabled: feature.boolean_value,
          percentageOfActors: feature.percentage_of_actors_value,
          actors: feature.current_visitor_actors_value
        }
      end
    }.to_json

    tag :meta, name: "features-datafile", content: datafile
  end

  def client_side_feature_flags(app_specific_flags: [])
    return @client_side_feature_flags if defined? @client_side_feature_flags

    possible_flags = GitHub::ClientSideFeatureFlags.js_flags

    FeatureFlag.vexi.preload(possible_flags, instrumentation_properties: {
      "code.namespace": "feature_flag_helper",
    })

    current_user_available = respond_to?(:current_user, true)
    actor = (GitHub.enterprise? || !current_user_available) ? nil : T.unsafe(self).current_user
    features = possible_flags.select do |flag|
      result = FeatureFlag.vexi.enabled(flag, actor, default: false)
      raise result.error if result.error # preserve previous error handling behavior
      result.value
    end

    @client_side_feature_flags = features.map { |feature| feature.to_sym }
    @client_side_feature_flags += app_specific_flags
  end

  def css_feature_flags
    return @css_feature_flags if defined? @css_feature_flags

    possible_flags = GitHub::ClientSideFeatureFlags.css_flags
    return if possible_flags.empty?

    FeatureFlag.vexi.preload(possible_flags, instrumentation_properties: {
      "code.namespace": "feature_flag_helper",
    })

    current_user_available = respond_to?(:current_user, true)
    actor = (GitHub.enterprise? || !current_user_available) ? nil : T.unsafe(self).current_user
    features = possible_flags.select do |flag|
      result = FeatureFlag.vexi.enabled(flag, actor, default: false)
      raise result.error if result.error # preserve previous error handling behavior
      result.value
    end

    @css_feature_flags = features.map { |feature| feature.to_sym }
  end
end
