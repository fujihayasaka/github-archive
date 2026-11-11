# typed: true
# frozen_string_literal: true

module PullRequests::PageData
  module Telemetry
    extend T::Helpers
    requires_ancestor { Object }

    # Wraps the execution of a block with telemetry timing measurements.
    #
    # @param block [Proc] The block of code to execute and measure
    # @return [Object] The return value of the executed block
    sig { type_parameters(:U).params(block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
    def with_telemetry(&block)
      tags = ["loader_name:#{self.class.name}"]

      # Calculate user context tags using the same pattern as ApplicationController
      logged_in = @current_user.present?
      is_staff = @current_user&.employee? || false

      GitHub::TaggingHelper.add_tag_unless_nil(tags, GitHub::TaggingHelper::LOGGED_IN_TAG, logged_in)
      GitHub::TaggingHelper.add_tag_unless_nil(tags, GitHub::TaggingHelper::STAFF_TAG, is_staff)

      GitHub.dogstats.distribution_time("pull_requests.page_data.load", tags: tags, &block)
    end
  end
end
