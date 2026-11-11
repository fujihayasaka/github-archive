# typed: true
# frozen_string_literal: true

module ApplicationController::CanonicalRequestDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern

  ORIGINAL_PATH_HEADER = "X-Viewproxy-Original-Path"

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :canonical_request
  end

  def canonical_request
    return @_canonical_request if defined?(@_canonical_request)

    original_path = request.headers[ORIGINAL_PATH_HEADER].presence

    @_canonical_request = if original_path
      ActionDispatch::Request.new(request.env.merge(Rack::PATH_INFO => original_path))
    else
      request
    end
  end

  def request_coming_from_voltron?
    # GLB deletes this header, so we can have confidence that
    # it's only present if voltron adds the header
    # (since voltron is in-between GLB and dotcom)
    request.headers[ORIGINAL_PATH_HEADER].present?
  end
end
