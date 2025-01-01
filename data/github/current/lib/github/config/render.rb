# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Render
      # Hide render diffs after this amount
      def max_render_diffs_per_page
        @max_render_diffs_per_page ||= 25
      end
      attr_writer :max_render_diffs_per_page

      # The raw domain for fetching rich content to render
      def render_raw_host_name
        GitHub.urls.raw_host_name
      end

      # A switch to disable or enable rendering rich content in iframes
      # across the site.
      #
      # Returns Boolean
      def render_enabled?
        true
      end
      attr_reader :render_enabled

      # A list of types that Viewscreen and Notebooks should limit itself to supporting.
      # Primarily used to restrict some formats in GHES.
      # An empty list indicates no limit.
      #
      # Returns an Array of Strings
      def render_type_filter
        @render_type_filter ||= []
      end

      # Takes a list of filters, or a string separated by ;
      # and fills in the render_type_filter
      #
      # Returns an Array of strings
      def render_type_filter=(filter)
        if filter.is_a? Array
          @render_type_filter = filter
        else
          @render_type_filter = filter.to_s.split(";")
        end
      end
    end
  end

  extend Config::Render
end
