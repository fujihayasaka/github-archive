# typed: true
# frozen_string_literal: true

module Codespaces
  class VscsApiUrl
    def self.for_codespace(codespace)
      return codespace.vscs_target_url if codespace.vscs_target_url.present? && codespace.vscs_target == :local
      new(location: codespace.location, vscs_target: codespace.vscs_target).url
    end

    def self.for_prebuild(prebuild)
      return prebuild.vscs_target_url if prebuild.vscs_target_url.present? && prebuild.vscs_target == :local
      new(location: prebuild.location, vscs_target: prebuild.vscs_target).url
    end

    def self.for_target(vscs_target)
      new(vscs_target: vscs_target).url
    end

    def initialize(location: nil, vscs_target: nil)
      @location = location
      @vscs_target = vscs_target.presence || Codespaces::Vscs.default_target
    end

    def url
      return default_api_url unless @location.present?

      Codespaces::VscsServiceStamp.find(region: @location, vscs_target: @vscs_target)&.api_url || default_api_url
    end

    private

    def default_api_url
      Codespaces::Vscs::TargetConfig.for(@vscs_target)&.api_url
    end

    def target_location_data
      GitHub.cache.fetch("codespaces_vscs_location_#{@vscs_target}", ttl: 6.hours) do
        path = "api/v1/locations"
        response = AnonymousVscsClient.new(api_url: GitHub::Config::VSCS_ENVIRONMENTS[@vscs_target][:api_url]).get(path)
        if response.success?
          JSON.parse(response.body)
        else
          {}
        end
      end
    end
  end
end
