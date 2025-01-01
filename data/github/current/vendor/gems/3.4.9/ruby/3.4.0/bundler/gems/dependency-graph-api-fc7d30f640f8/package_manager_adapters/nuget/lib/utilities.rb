require "failbot"
require "json"
require "scrolls"

module Logging
  def logger
    # Initialize Scrolls (tagged logging) with our context if we haven't already
    @logger ||= Scrolls.init(
      global_context: {
        "gh.dependency_graph.package_manager" => "nuget",
        "code.namespace" => self.class.name,
       },
      timestamp: true,
    )

    # Return the Scrolls class so we can call methods like `info`
    Scrolls
  end
end

module ParseJson
  def parse_json(json_object)
    begin
      JSON.parse(json_object)
    rescue JSON::ParserError => e
      logger.error e.inspect
      Failbot.report(e, "gh.dependency_graph.package_repo_json_object" => json_object)
    end
  end
end
