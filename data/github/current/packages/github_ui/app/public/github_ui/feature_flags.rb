# typed: strict
# frozen_string_literal: true

module GitHubUI
  class FeatureFlags
    # All client feature flags are loaded from following file:
    #   ui/packages/feature-flags/client-feature-flags.ts

    sig { returns(T::Array[Symbol]) }
    def self.js_flags
      GitHubUI::Manifest.new.feature_flags(type: :js)
    end

    sig { returns(T::Array[Symbol]) }
    def self.css_flags
      GitHubUI::Manifest.new.feature_flags(type: :css)
    end

    sig { params(key: Symbol).returns(T::Array[Symbol]) }
    def self.memex_flags(key)
      flags = GitHubUI::Manifest.new.nested_feature_flags(type: :memex)
      Array(flags[key.to_sym])
    end
  end
end
