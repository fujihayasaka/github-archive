require "memory_profiler"

module DependencyGraph
  class MemoryProfilerMiddleware
    def initialize(app)
      @app = app
    end

    # Note that we use request.GET rather than request.params throughout this
    # class because a) we only expect parameters to be passed to us through the
    # URL's query string, b) we don't want to spend time inspecting potentially
    # large POST bodies, and c) the POST bodies may be in encodings that Rack
    # doesn't expect but that our Rails app handles just fine. See
    # https://github.com/github/github/issues/31228.
    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless request.GET.has_key?("memprof")

      # query strings break twirp routing
      env["QUERY_STRING"] = "" if env["PATH_INFO"].starts_with?("/twirp/")

      status = headers = body = nil

      report = MemoryProfiler.report do
        status, headers, body = @app.call(env)
        body.close if body.respond_to?(:close)
      end

      out = StringIO.new
      report.pretty_print(out)

      body = out.string
      headers["Content-Type"] = "text/plain"
      filename = "memory_profile_#{request.path.gsub("/", "_")}_#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.txt"
      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""

      # Make sure the actual response has a correct content-length instead
      # of whatever the wrapped app generated.
      headers["Content-Length"] = body.bytesize.to_s
      # Ensure that the report can be returned when status is 204 No Content
      status = status == 204 ? 200 : status
      Rack::Response.new(body, status, headers).finish
    end
  end
end
