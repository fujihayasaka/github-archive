# frozen_string_literal: true

# originally shamelessly copied from https://github.com/github/dependency-graph-api/blob/3fb6f8d8f410b6fa6a8b5427bba4f6f75676e846/lib/dependency_graph/flamegraph_middleware.rb#L4
# simplified since we don't use other flamegraph formats (yet??)

module AdvisoryDB
  class FlamegraphMiddleware
    INTERVAL_DEFAULT = 1000
    INTERVAL_MIN = 10

    def initialize(app)
      @app = app
    end

    # The output can be uploaded to https://vernier.prof/ for viewing.
    # Adding a "?flamegraph" to an inbox page will give you a downloaded prof.
    #
    # If you're profiling a timeout, you may find ?write_flamegraph_to_tmp useful.
    #
    # Note that we use request.GET rather than request.params throughout this
    # class because a) we only expect parameters to be passed to us through the
    # URL's query string, b) we don't want to spend time inspecting potentially
    # large POST bodies, and c) the POST bodies may be in encodings that Rack
    # doesn't expect but that our Rails app handles just fine. See
    # https://github.com/github/github/issues/31228.
    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless request.GET.key?("flamegraph")

      interval = if request.GET["flamegraph_interval"].present?
                   request.GET["flamegraph_interval"].to_i
                 else
                   INTERVAL_DEFAULT
                 end
      interval = INTERVAL_MIN if interval < INTERVAL_MIN

      status = headers = body = nil

      allocation_sample_rate = request.GET["flamegraph_allocation_sample_rate"].to_i
      result = Vernier.trace(interval: interval, allocation_sample_rate: allocation_sample_rate, hooks: [:rails]) do
        status, headers, body = @app.call(env)
      end

      # Firefox output format, used by https://vernier.prof/
      body = result.to_gecko

      filename = "profile_#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.vernier.json"

      File.write("/tmp/#{filename}", body) if request.GET.key?("write_flamegraph_to_tmp")

      headers["Content-Type"] = "application/json; charset=utf-8"
      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      headers["Content-Length"] = body&.bytesize.to_s
      status = 200

      Rack::Response.new(body, status, headers).finish
    end
  end
end
