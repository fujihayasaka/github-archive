# typed: strict
# frozen_string_literal: true

module Site
  module Fullstory
    class CaptureComponent < ApplicationComponent
      extend T::Sig
      include UrlHelper

      sig { returns(String) }
      def recording_script_domain
        StaticAssetPaths::asset_host_url
      end

      sig { returns(T::Boolean) }
      def render?
        !logged_in?
      end
    end
  end
end
