# typed: true
# frozen_string_literal: true

class ApiRoutes::WipPrReport
  SKIPPABLE_NAMESPACES = %w(
    Api::Internal
    Api::Staff
    Api::Policies
  )
  def self.collector
    ApiRoutes::ASTRouteCollector
  end

  attr_reader :collection
  def initialize(collections)
    namespace = ENV["NAMESPACE"]
    @collection = collections.find { |collection| collection.namespace == ENV["NAMESPACE"] }
  end

  def emoji(enabled)
    if enabled
      ":heavy_check_mark:"
    else
      ":x:"
    end
  end

  def print
    title = collection.namespace.split("::").last.titleize
    endpoints = collection.endpoints.reject(&:audited?).sort_by(&:route)

    todos = endpoints.map do |endpoint|
      "- [ ] (%s %s) `%s`" % [emoji(endpoint.enabled_for_integrations?), emoji(endpoint.enabled_for_user_via_integrations?), endpoint]
    end

    server_to_server_endpoints = endpoints.reject do |endpoint|
      endpoint.enabled_for_integrations?
    end.map do |endpoint|
      "- [`%s`](%s)" % [endpoint.to_docstyle, endpoint.docs_url]
    end
    server_to_server = server_to_server_endpoints.empty? ? "_No additional endpoints enabled._" : "```\n%s\n```" % server_to_server_endpoints.join("\n")

    user_to_server_endpoints = endpoints.reject do |endpoint|
      endpoint.verb == :get || endpoint.enabled_for_user_via_integrations?
    end.map do |endpoint|
      "- [`%s`](%s)" % [endpoint.to_docstyle, endpoint.docs_url]
    end
    user_to_server = user_to_server_endpoints.empty? ? "_No additional endpoints enabled._" : "```\n%s\n```" % user_to_server_endpoints.join("\n")

    audited_endpoints = endpoints.select do |endpoint|
      endpoint.verb == :get && endpoint.enabled_for_integrations?
    end.map do |endpoint|
      "- `%s`" % endpoint.to_docstyle
    end

    puts <<-TXT
:construction: _Nothing to see here yet. Move along folks._ :construction:

**TODO**

#{todos.join("\n")}

---

Part of batch [paste URL of batch deploy branch here].

[paste table here]

### Enabled for Server-to-Server

#{server_to_server}

### Enabled for User-to-Server

#{user_to_server}

### Audited without enabling anything

#{audited_endpoints.join("\n")}

### Notes

    TXT
  end
end
