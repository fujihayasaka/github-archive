# frozen_string_literal: true

require "github_helpers"

module ChatopUpdaterEcosystem
  extend ActiveSupport::Concern

  SENTRY_PROJECT = "1451818"
  FIDO_PROTECTED_ACTIONS = %i(set_ecosystem_version).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    before_action :require_fido_2fa, only: FIDO_PROTECTED_ACTIONS

    chatop :ecosystem_versions,
           /ecosystem[-_]versions\s+(?<environment>\w+)/,
           "ecosystem-versions ENV - Get the updater ecosystem versions" do
      env = normalize_env(jsonrpc_params[:environment].downcase)
      if env == ""
        jsonrpc_failure "Didn't recognise that, must be "\
                        "`.dependabot ecosystem-versions stage|prod`"
        return
      end

      versions = UpdaterVersion.where(env: env).order(ecosystem: :desc)
      str = versions.map { |v| "#{v.ecosystem}: #{v.version}" }.join("\n")

      jsonrpc_success "Environment #{env} ecosystem versions: \n```\n#{str}\n```"
    end

    chatop :set_ecosystem_version,
           /set[-_]ecosystem[-_]version\s+(?<env>\w+)\s+(?<ecosystem>[\w*]+)\s+(?<version>[\\.\-\w]+)/,
           "set-ecosystem-version ENV ECOSYSTEM VERSION - Set the updater version" do
      env = normalize_env(jsonrpc_params[:env].downcase)
      if env == ""
        jsonrpc_failure "Didn't recognise that, must be "\
                        "`.dependabot set-ecosystem-version stage|prod ECOSYSTEM VERSION`"
        return
      end

      ecosystem = jsonrpc_params[:ecosystem]
      unless ecosystem == "*" || ParseConfigFile::PACKAGE_MANAGER_LOOKUP.key?(ecosystem)
        jsonrpc_failure "Ecosystem must be `*` or the [dependabot.yml name]" \
                        "(https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/" \
                        "configuration-options-for-the-dependabot.yml-file#package-ecosystem)"
        return
      end

      ecosystems = if ecosystem == "*"
                     ParseConfigFile::PACKAGE_MANAGER_LOOKUP.keys
                   else
                     [ecosystem]
                   end

      version = jsonrpc_params[:version]
      previous_versions = UpdaterVersion.where(env: env, ecosystem: ecosystems).to_a

      # Verify the GHCR image(s) exists, otherwise a typo or upload failure would cause job failures.
      not_exists = ecosystems.find { |eco| !ghcr_image_exists?(eco, version) }
      if not_exists
        jsonrpc_failure "Updater `#{not_exists}/#{version}` not found in GHCR"
        return
      end

      UpdaterVersion.transaction do
        ecosystems.each do |eco|
          UpdaterVersion.upsert({ env: env, ecosystem: eco, version: version })
        end
      end

      response = []
      response << if ecosystems.length == 1
                    "Updated '#{env}' updater version: `#{ecosystem}/#{version}`"
                  else
                    "Updated all '#{env}' updater versions to: `#{version}`"
                  end
      response << "[Sentry](https://github.sentry.io/releases/#{version}/?project=#{SENTRY_PROJECT})\n"
      if previous_versions.any?
        response << "Previous versions:"
        response << "```"
        response << previous_versions.map { |v| "#{v.version}: #{v.ecosystem}" }.join("\n")
        response << "```\n"
      end

      jsonrpc_success response.join("\n")
    end

    private

    def normalize_env(env)
      if env.include?("stag")
        "stage"
      elsif env.include?("prod")
        "prod"
      else
        ""
      end
    end

    def ghcr_image_exists?(ecosystem, version)
      token_uri = URI("https://ghcr.io/token?scope=repository:dependabot/dependabot-updater-#{ecosystem}:pull")
      token_res = Net::HTTP.get(token_uri)
      token = JSON.parse(token_res)["token"]

      manifest_uri = URI("https://ghcr.io/v2/dependabot/dependabot-updater-#{ecosystem}/manifests/#{version}")
      http = Net::HTTP.new(manifest_uri.host, manifest_uri.port)
      http.use_ssl = true
      req = Net::HTTP::Head.new(manifest_uri)
      req["Accept"] = "application/vnd.oci.image.index.v1+json"
      req["Authorization"] = "Bearer #{token}"
      res = http.request(req)

      res.code.to_i == 200
    end
  end
  # rubocop:enable Metrics/BlockLength
end
