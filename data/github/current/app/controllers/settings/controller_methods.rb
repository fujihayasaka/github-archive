# typed: true
# frozen_string_literal: true

module Settings::ControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :set_context_title, if: :header_redesign_enabled?
  end

  def set_context_title
    context_region_preset :settings
  end

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
