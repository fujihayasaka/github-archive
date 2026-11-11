# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Spokesd
      attr_accessor :spokesd_url, :spokesd_client_role

      def spokesd_enabled?
        return @spokesd_enabled if defined?(@spokesd_enabled)
        @spokesd_enabled = evaluate_spokesd_enabled
      end

      def spokesd_tmp_key_file
        return @spokesd_tmp_key_file.path if @spokesd_tmp_key_file

        @spokesd_tmp_key_file = Tempfile.new("spokesd-key", Rails.root.join("tmp").expand_path)
        @spokesd_tmp_key_file.write(GitHub.environment.fetch(spokesd_key_env))
        @spokesd_tmp_key_file.flush
        @spokesd_tmp_key_file.path
      end

      def spokesd_tmp_cert_file
        return @spokesd_tmp_cert_file.path if @spokesd_tmp_cert_file

        @spokesd_tmp_cert_file = Tempfile.new("spokesd-cert", Rails.root.join("tmp").expand_path)
        @spokesd_tmp_cert_file.write(GitHub.environment.fetch(spokesd_cert_env))
        @spokesd_tmp_cert_file.flush
        @spokesd_tmp_cert_file.path
      end

      def spokesd_certs
        if GitHub.environment.fetch(spokesd_key_env, "") != ""
          [spokesd_cert_file("chain.pem"), spokesd_tmp_key_file, spokesd_tmp_cert_file]
        elsif spokesd_cert_present?
          files = ["chain.pem", "#{spokesd_cert_name}.key", "#{spokesd_cert_name}.crt"]
          files.map { |f| spokesd_cert_file(f) }
        else
          nil
        end
      end

      # By default, use only Spokesd to load repository routes. For dotcom,
      # spokesd is reliable enough that we want to do this. We don't have good
      # visibility into how often GHES uses the GitHub::DGit fallback code, so
      # this config option exists. If needed, GHES admins can bring back the
      # fallback code by running this:
      #   ghe-config app.github.spokesd-fallback-enabled true
      attr_writer :spokesd_fallback_enabled
      def spokesd_fallback_enabled?
        @spokesd_fallback_enabled
      end

      private

      def evaluate_spokesd_enabled
        # Not if the URL is missing
        spokesd_url.present?
      end

      def spokesd_use_tls?
        !!spokesd_url&.start_with?("https")
      end

      def spokesd_cert_present?
        File.file?(spokesd_cert_file("#{spokesd_cert_name}.key"))
      end

      def spokesd_cert_name
        if spokesd_client_role.present?
          "github-#{spokesd_client_role}"
        else
          "github-#{GitHub.role}"
        end
      end

      def spokesd_cert_prefix
        if spokesd_client_role.present?
          "GITHUB_#{spokesd_client_role.upcase.sub('-', '_')}_SPOKESD_CLIENT"
        else
          "GITHUB_#{GitHub.role.to_s.upcase.sub('-', '_')}_SPOKESD_CLIENT"
        end
      end

      def spokesd_cert_env
        "#{spokesd_cert_prefix}_CERT"
      end

      def spokesd_key_env
        "#{spokesd_cert_prefix}_CERT_KEY"
      end

      def spokesd_cert_file(name)
        File.join(ENV["RAILS_ROOT"], "config", "service_certificates", "spokesd", name)
      end
    end
  end

  extend Config::Spokesd
end
