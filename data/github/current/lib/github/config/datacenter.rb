# typed: false
# frozen_string_literal: true

require "github/config/metadata"

module GitHub
  module Config
    module Datacenter
      def default_datacenter
        "DEFAULT_DC"
      end

      def default_site
        "DEFAULT_SITE"
      end

      def default_rack
        "DEFAULT_RACK"
      end

      # The effective datacenter of the current host.
      def datacenter
        local_datacenter || metadata_datacenter || default_datacenter
      end

      def site
        local_site || metadata_site || default_site
      end

      # Set this to override the automatically determined value for datacenter.
      #
      # Enterprise sets this with ENV["ENTERPRISE_LOCAL_DATACENTER"].
      # Tests set this.
      # Dotcom should not set this.
      attr_accessor :local_datacenter
      attr_accessor :local_site

      # The datacenter of the current host, as read from /etc/github/metadata.json in prod.
      def metadata_datacenter
        return @metadata_datacenter if defined?(@metadata_datacenter)
        @metadata_datacenter = get_datacenter_from_metadata
      end

      def metadata_site
        return @metadata_site if defined?(@metadata_site)
        @metadata_site = get_site_from_metadata
      end

      def use_value_from_metadata?
        Rails.env.production? && !GitHub.enterprise?
      end

      def get_datacenter_from_metadata
        get_metadata_or_nil("datacenter")
      end

      def get_site_from_metadata
        get_metadata_or_nil("site")
      end

      def get_metadata_or_nil(key)
        if use_value_from_metadata?
          read_metadata.fetch(key)
        else
          nil
        end
      rescue Errno::ENOENT, GitHub::JSON::ParseError, NoMethodError, KeyError => e
        if defined?(::Failbot) && !::Failbot.already_reporting
          # avoid trying to read metadata.json again, so that Failbot doesn't get spammed, and to avoid an infinite loop!
          instance_variable_set("@metadata_#{key}", nil)
          ::Failbot.report!(e)
        end
        nil
      end

    end
  end

  extend Config::Datacenter
end
