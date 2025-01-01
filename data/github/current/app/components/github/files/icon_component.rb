# typed: true
# frozen_string_literal: true

module GitHub
  module Files
    class IconComponent < ApplicationComponent
      def initialize(type:, **args)
        @args = args.merge(
          case type
          when :directory
            {
              "aria-label" => "Directory",
              :classes => "hx_color-icon-directory",
              :icon => "file-directory-fill"
            }
          when :submodule
            {
              "aria-label" => "Submodule",
              :classes => "hx_color-icon-directory",
              :icon => "file-submodule"
            }
          when :symlink_directory
            {
              "aria-label" => "Symlink Directory",
              :classes => "hx_color-icon-directory",
              :icon => "file-submodule"
            }
          when :symlink_file
            {
              "aria-label" => "Symlink Directory",
              :classes => "hx_color-icon-directory",
              :icon => "file-submodule"
            }
          else
            {
              "aria-label" => "File",
              :color => :muted,
              :icon => "file"
            }
          end
        )
      end

      def call
        primer_octicon(**@args)
      end
    end
  end
end
