# typed: true
# frozen_string_literal: true

module FeatureFlagHelper
  include Kernel

  def feature_enabled_for_current_user?(feature_name:, subject: nil)
    if subject
      GitHub.flipper[feature_name].enabled?(subject)
    else
      T.unsafe(self).logged_in? && GitHub.flipper[feature_name].enabled?(T.unsafe(self).current_user)
    end
  end

  def feature_enabled_for_current_visitor?(feature_name:)
    T.unsafe(self).current_visitor && GitHub.flipper[feature_name].enabled?(User::CurrentVisitorActor.from_current_visitor(T.unsafe(self).current_visitor.octolytics_id))
  end

  def feature_enabled_globally_or_for_user?(feature_name:, subject: nil)
    GitHub.flipper[feature_name].enabled? || feature_enabled_for_current_user?(feature_name: feature_name, subject: subject)
  end

  def feature_enabled_for_user_or_current_visitor?(feature_name:, subject: nil)
    return feature_enabled_globally_or_for_user?(feature_name: feature_name, subject: subject) if subject

    feature_enabled_globally_or_for_user?(feature_name: feature_name, subject: subject) || feature_enabled_for_current_visitor?(feature_name: feature_name)
  end

  def features_datafile_tag
    T.bind(self, ApplicationHelper)
    return if datafile_features.blank?
    features = FlipperFeature.where(name: datafile_features)

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

    possible_flags = GitHub::ClientSideFeatureFlags::FLAGS
    GitHub.flipper.preload(possible_flags + [:vexi_preload_feature_flag_helper])

    if GitHub.flipper[:vexi_preload_feature_flag_helper].enabled?
      FeatureFlag.vexi.preload(possible_flags)
    end

    current_user_available = respond_to?(:current_user, true)
    actor = (GitHub.enterprise? || !current_user_available) ? nil : T.unsafe(self).current_user
    features = possible_flags.select { |flag| actor.nil? ? GitHub.flipper[flag].enabled? : actor.feature_enabled?(flag) }
    @client_side_feature_flags = features.map { |feature| feature.to_sym }
    @client_side_feature_flags += app_specific_flags
  end

  def css_feature_flags
    return @css_feature_flags if defined? @css_feature_flags

    possible_flags = GitHub::ClientSideFeatureFlags::CSS_FLAGS
    GitHub.flipper.preload(possible_flags + [:vexi_preload_feature_flag_helper])

    if GitHub.flipper[:vexi_preload_feature_flag_helper].enabled?
      FeatureFlag.vexi.preload(possible_flags)
    end

    current_user_available = respond_to?(:current_user, true)
    actor = (GitHub.enterprise? || !current_user_available) ? nil : T.unsafe(self).current_user
    features = possible_flags.select { |flag| actor.nil? ? GitHub.flipper[flag].enabled? : actor.feature_enabled?(flag) }
    @css_feature_flags = features.map { |feature| feature.to_sym }
  end
end
