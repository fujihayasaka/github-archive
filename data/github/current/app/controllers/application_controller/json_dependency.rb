# typed: true
# frozen_string_literal: true

# The default Rails JSON parsing behavior was [disabled][disable_json] in
# github/github in 2014. Now, there are some valid use cases for sending JSON
# payloads to the Rails application with a `"Content-type: application/json"`
# header.
#
# We can't re-enable the JSON parsing behavior wholesale, because it would
# break [at least one place][json_form] that mistakenly sends non-JSON data
# with a JSON content-type header.
#
# For now, endpoints that want to parse request bodies as JSON must explicitly
# include this module and call `before_action :parse_json_params`.
#
# Long-term, we should [investigate][json_issue] re-enabling the default Rails
# behavior.
#
# [disable_json]: https://github.com/github/github/pull/21699
# [json_form]: https://github.com/github/github/pull/175054/files/8dedb6c8ec75811f05540a36bc74f95805559734#diff-adeb8b4f9c27b182a9d1087c37ab26fc072f396c8070455594f78b693a9c06b0R157
# [json_issue]: https://github.com/github/pse-architecture/issues/454
module ApplicationController::JsonDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  # If the request contains a JSON hash payload, parse it as JSON and raise if
  # it is invalid.
  def parse_json_params
    if request.content_mime_type == Mime[:json]
      data = GitHub::JSON.parse(request.raw_post)
      data.each { |k, v| params[k] = v if !params.key?(k) } if data.is_a?(Hash)
    end
  end

  # If the request contains a JSON hash payload, parse it as JSON or return a
  # bad request response if it is invalid.
  def try_parse_json_params
    parse_json_params
  rescue Yajl::ParseError
    head :bad_request
  end
end
