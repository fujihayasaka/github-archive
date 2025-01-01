# typed: strict
# frozen_string_literal: true

module Sponsors::AdminableControllerValidations
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController }

  include Sponsors::SharedControllerMethods

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :sponsorable_required
    before_action :sponsorable_adminable_by_current_user_required
    before_action :sponsorable_owned_by_current_user_required_for_non_get_requests
    before_action :enabled_sponsors_listing_required
    before_action :sudo_filter
  end
end
