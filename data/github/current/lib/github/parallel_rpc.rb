# typed: true
# frozen_string_literal: true

module GitHub
  module ParallelRpc
    def parallel_rpc(fileservers, command, args: [], kwargs: {}, timeout: nil, connect_timeout: nil)
      routes = fileservers.map { |fs| fs.to_route("/") }
      route_urls = Hash[routes.map { |route| [route.rpc_url, route] }]

      options = {}
      options[:timeout] = timeout unless timeout.nil?
      options[:connect_timeout] = connect_timeout unless connect_timeout.nil?

      answers, errors = ::GitRPC::send_multiple(route_urls.keys, command, args, kwargs, options)

      answers = Hash[answers.map { |url, answer| [route_urls[url].original_host, answer] }]
      errors = Hash[errors.map { |url, error| [route_urls[url].original_host, error] }]

      [answers, errors]
    end
  end
end
