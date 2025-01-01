# typed: true
# frozen_string_literal: true

module GitHub
  class ClientSideFeatureFlags
    # All client feature flags are loaded from following file:
    #   ui/packages/feature-flags/client-feature-flags.ts

    def self.js_flags
      GitHubUI::Manifest.new.feature_flags(type: :js)
    end

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
