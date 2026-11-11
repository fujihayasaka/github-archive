# typed: true
# frozen_string_literal: true

module Settings::Education::DeveloperPackApplications::SharedControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :dotcom_required
    before_action :login_required
    before_action :require_feature
  end

  sig { void }
  def require_feature
    render_404 unless user_or_global_feature_enabled?("education-dev-pack-application")
  end

  sig { returns(Education::Twirp::SchoolsClient) }
  memoize def schools_client
    Education::Twirp::SchoolsClient.new(user: current_user)
  end
end
