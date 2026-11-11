# typed: true
# frozen_string_literal: true

class ContentAuthorizer::ReportContentAuthorizer < ContentAuthorizer

  def initialize(actor, operation, data)
    super
    @content = data[:reported_content]
  end

  # Public: All of the authorization errors blocking the given actor from
  # reporting content. These should be assembled in priority order
  # (from most urgent/important to least) because the API will only
  # return the first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    errors = []

    unless feature_available_for_this_content?
      errors << ContentAuthorizationError::FeatureNotAvailable.new
      return errors if fail_fast
    end

    errors
  end

  private

  def feature_available_for_this_content?
    @content.async_viewer_can_report_to_maintainer?(actor).sync
  end
end
