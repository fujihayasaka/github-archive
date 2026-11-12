require "httparty"
require_relative "utilities"
require "failbot"

module Nuget
  class FjordSink
    include ParseJson, Logging

    attr_accessor :url, :checkpoints_url, :package_releases

    def initialize(fjord_url:, checkpoints_url:)
      @url = fjord_url
      @checkpoints_url = checkpoints_url
      @package_releases = []
    end

    # GET Checkpoint /checkpoints/:id
    def get_checkpoint(id)
      response = HTTParty.get(checkpoints_url + "/checkpoints/#{id}")
      parse_json(response.body)["value"]
    end

    # PUT Checkpoint /checkpoints/:id
    def set_checkpoint(id, value)
      response = HTTParty.put(checkpoints_url + "/checkpoints/#{id}", { body: { value: value } })
      parse_json(response.body)["value"]
    end

    # POST Package Release Hydro Event /api/v1/events
    def flush_package_releases
      payload = {}
      payload["events"] = package_releases.each do |release|
        release["cluster"] = url.include?("docker") ? "localhost" : nil
        release["schema"] = "hydro.schemas.github.dependencygraph.v0.PackageRelease"
      end

      response = HTTParty.post(url + "/api/v1/events", headers: { "Content-Type": "application/json", "ClientID": "dependency-graph-nuget" }, body: payload.to_json)
      if response.success?
        logger.info("[FJORD] Flush of packages was a success!")
        self.package_releases = []
        return true
      else
        logger.info("[FJORD] Flush failed with error code #{response.code}")
        logger.debug response
        Failbot.report(RuntimeError.new, message: "[FJORD] Flush of nuget packages failed", response: response)
        return false
      end
    end

    def <<(release)
      self.package_releases << release
    end
  end
end
