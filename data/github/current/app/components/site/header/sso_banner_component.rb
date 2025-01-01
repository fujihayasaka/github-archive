# typed: true
# frozen_string_literal: true

module Site
  module Header
    class SsoBannerComponent < ApplicationComponent
      include ConditionalAccessHelper

      attr_reader :orgs

      def initialize(orgs: [], **system_arguments)
        @orgs = orgs
        @system_arguments = system_arguments
      end

      def return_to
        # todo: handle return-to client-side to update the return_to param after turbo nav events
        # See https://github.com/github/platform-ux/issues/1290
        nil
      end
    end
  end
end
