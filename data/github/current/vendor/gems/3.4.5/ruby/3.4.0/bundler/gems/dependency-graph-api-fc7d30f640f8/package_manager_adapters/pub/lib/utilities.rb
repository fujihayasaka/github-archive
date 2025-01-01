require "failbot"
require "scrolls"

module Logging
  def logger
    # Initialize Scrolls (tagged logging) with our context if we haven't already
    @logger ||= Scrolls.init(
      global_context: {
        "gh.dependency_graph.package_manager" => "pub",
        "code.namespace" => self.class.name,
      },
      timestamp: true,
    )

    # Return the Scrolls class so we can call methods like `info`
    Scrolls
  end
end
