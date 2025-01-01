# typed: true
# frozen_string_literal: true

module Signups
  module FeatureHelperDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    included do
      # Global helpers for general use
      T.bind(self, T.class_of(ApplicationController))
      helper_method :feature_enabled_if_even_octo_cookie_id?
    end

    sig { returns T::Boolean }
    def feature_enabled_if_even_octo_cookie_id?
      octo_id = current_visitor&.octolytics_id
      return false if octo_id.nil?

      last_digit = octo_id.scan(/\d/).last.to_i
      last_digit.even?
    end
  end
end
