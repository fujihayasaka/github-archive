# typed: strict
# frozen_string_literal: true

module Site
  module Fullstory
    class CaptureComponent < ApplicationComponent
      include UrlHelper

      sig { params(allow_logged_in: T::Boolean).void }
      def initialize(allow_logged_in: false)
        @allow_logged_in = allow_logged_in
      end

      sig { returns(String) }
      def recording_script_domain
        StaticAssetPaths::asset_host_url
      end

      sig { returns(T::Boolean) }
      def render?
        @allow_logged_in || !logged_in?
      end
    end
  end
end
