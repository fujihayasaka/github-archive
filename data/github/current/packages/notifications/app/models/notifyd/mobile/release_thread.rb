# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    class ReleaseThread
      include Thread

      sig { params(release: ::Release).void }
      def initialize(release:)
        @release = release
      end

      sig { override.returns(T.nilable(String)) }
      def id
        @release.permalink(include_host: false)
      end

      sig { override.returns(String) }
      def type
        "release"
      end
    end
  end
end
