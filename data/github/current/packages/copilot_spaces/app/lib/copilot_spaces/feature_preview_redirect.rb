# typed: true
# frozen_string_literal: true

module CopilotSpaces
  module FeaturePreviewRedirect
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    # Custom copilots are enabled for:
    # 1. users with the :copilot_custom_copilots feature flag, which some will be individually opted into
    # 2. The following types of users with the :copilot_custom_copilots_feature_preview feature flag:
    #    a. users with Copilot Individual (CI) licenses, for whom preview features are always enabled
    #    b. CB and CE users whose orgs have opted into preview features
    #    c. Copilot Free users, signified by `has_limited_access` on their plan
    def copilot_spaces_enabled?
      (user_feature_enabled?(:copilot_custom_copilots) ||
        (user_feature_enabled?(:copilot_custom_copilots_feature_preview) &&
        (current_copilot_user_v2&.beta_features_github_chat_enabled? || current_copilot_user_v2&.has_limited_access?))
      )
    end

    def require_copilot_spaces_feature_enabled
      render_404 unless copilot_spaces_enabled?
    end

    def redirect_to_custom_copilots_feature_preview
      redirect_to "https://github.com/features/preview/copilot-spaces"
    end
  end
end
