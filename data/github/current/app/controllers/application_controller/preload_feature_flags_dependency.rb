# typed: true
# frozen_string_literal: true

module ApplicationController::PreloadFeatureFlagsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  include ApplicationController::ApplicationLayoutFeatures

  class_methods do
    include Kernel

    # Public: Define an array of features that should be preloaded for this controller/action,
    # in order to avoid N calls to memcache (1 per feature per request).
    # This is meant to be called throughout the controller hierarchy in order to
    # avoid child controllers needing to worry about layout-level flag preloading.
    #
    # For now, features are only preloaded if the requested format is HTML, since
    # many feature checks occur in ERB layouts.
    #
    # features - The Array of symbols representing the features to preload.
    # only - Optional symbol or array of symbols representing the actions that
    #        should preload these features. If omitted, all actions in this controller will
    #        preload this list of features.
    #
    # Examples
    #
    #   preload_features [:my_whole_controller_needs_this]
    #   preload_features [:specific_feature], only: :index
    #   preload_features [:kind_of_specific_feature], only: [:index, :show]
    def preload_features(features, only: nil)
      T.bind(self, T.class_of(ApplicationController))
      if only
        Array(only).each do |action|
          new_set = features_to_preload_by_action[action].union(features)

          self.features_to_preload_by_action =
            self.features_to_preload_by_action.merge(action => new_set)
        end
      else
        self.features_to_preload += features.to_set
      end
    end
  end

  included do
    T.bind(self, Class)
    class_attribute :features_to_preload
    class_attribute :features_to_preload_by_action

    T.bind(self, T.class_of(ApplicationController))
    before_action :do_feature_preload

    self.features_to_preload = APPLICATION_LAYOUT_FEATURES.dup
    self.features_to_preload_by_action = HashWithIndifferentAccess.new { |k, v| k[v] = Set.new }
  end

  def do_feature_preload
    return unless request.format.try(:html?)
    return if GitHub.enterprise?

    # Preloading can be slow in tests, so we skip it by default there.
    return if ApplicationController::PreloadFeatureFlagsDependency.skip_feature_preload_in_tests?

    action_features = features_to_preload_by_action[action_name]
    general_features = features_to_preload
    all_features = action_features.union(general_features).to_a.sort

    FeatureFlag.vexi.preload(all_features, instrumentation_properties: {
      "code.namespace": self.class.name&.underscore,
    })
  end

  # Returns true by default when running in tests to skip preload.
  # This wrapper function allows tests that want to enable preload to do so via stubbing this method,
  # without needing to stub the entire GitHub::AppEnvironment.test? method, which can cause other side effects.
  def self.skip_feature_preload_in_tests?
    GitHub::AppEnvironment.test?
  end
end
