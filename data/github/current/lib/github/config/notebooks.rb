# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module NotebooksConfig
      # Defaults to "/notebooks" and can be overridden
      # by setting ENTERPRISE_NOTEBOOKS_PATH_PREFIX="/foo/bar" when running dotcom
      def notebooks_path_prefix
        return @notebooks_path_prefix if defined?(@notebooks_path_prefix)
        @notebooks_path_prefix = "/notebooks"
      end
      attr_writer :notebooks_path_prefix
    end
  end

  extend Config::NotebooksConfig
end
