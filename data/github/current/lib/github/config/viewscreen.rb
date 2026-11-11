# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ViewscreenConfig
      # Defaults to "/viewscreen" and can be overridden
      # by setting ENTERPRISE_VIEWSCREEN_PATH_PREFIX="/foo/bar" when running dotcom
      def viewscreen_path_prefix
        return @viewscreen_path_prefix if defined?(@viewscreen_path_prefix)
        @viewscreen_path_prefix = "/viewscreen"
      end
      attr_writer :viewscreen_path_prefix
    end
  end

  extend Config::ViewscreenConfig
end
