# typed: true
# frozen_string_literal: true

module ApplicationController::OriginTrialDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :add_origin_trial_header
  end

  def add_origin_trial_header
    return unless logged_in?
    trials = GitHub::OriginTrials::active_trials(user: current_user)
    return unless trials.any?
    response.headers["Origin-Trial"] = trials.map(&:token).join(",")
  end
end
