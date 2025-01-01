# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("gitauth.gitauth_request") do |payload|
    request_context = payload[:request_context]

    message = {
      request_id: request_context[:request_id],
      mirrored_request_id: payload[:mirrored_request_id],
      action: payload.dig(:request_params, "action"),
      http_status: payload[:http_status],
      gitauth_status: payload[:gitauth_status],
      repo: request_context[:repo],
      member: request_context[:filtered_member]&.to_s&.dup&.force_encoding(Encoding::UTF_8)&.scrub!,
      protocol: request_context[:protocol],
      svnbridge_mode: request_context[:svnbridge_mode],
      actor_ip: request_context[:actor_ip],
      server_id: request_context[:server_id],
      cache_enabled: request_context[:cache_enabled],
      result_from_cache: request_context[:result_from_cache],
      request_headers: payload[:request_headers].to_json,
      request_params: payload[:request_params].to_json,
      # CAP results are not returned to babeld but are useful for analysis and debugging
      cap_results: payload[:cap_results],
      # The response to babeld contains formatted stats, routes, audit log pack kvs, commit refs pack ctx, and postrx hook ctx
      response: payload[:response],
      response_headers: payload[:response_headers].to_json,
      duration_ms: payload[:duration_ms],
    }

    publish(message, schema: "github.gitauth.v0.GitAuthRequest", publisher: GitHub.hydro_request_analytics_publisher)
  end
end
