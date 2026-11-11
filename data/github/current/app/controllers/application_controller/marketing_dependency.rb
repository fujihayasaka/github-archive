# typed: true
# frozen_string_literal: true

module ApplicationController::MarketingDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :marketing_page?
  end

  sig { returns(T::Boolean) }
  def marketing_page?
    controller = T.let(T.unsafe(self), T.any(ActionController::Base, ApplicationController)) # Global controller object
    request = T.let(T.unsafe(self).request, ActionDispatch::Request) # Global request object, passed from the controller
    return true if controller.class == DashboardController && request.path == "/" && !T.unsafe(self).logged_in?
    return true if controller.class.ancestors.include?(Site::BaseController)
    false
  end
end
