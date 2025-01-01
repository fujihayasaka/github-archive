# Opt into this middleware by calling your favorite API endpoints with ?dump_sql_queries
module DependencyGraph
  module SQLQueriesContainer
    def self.add_query(sql_query)
      return if (queries = self.get_queries).nil?
      queries << sql_query
      self.set_queries(queries)
    end

    def self.add_error(error_string)
      return if (queries = self.get_queries).nil?
      # This is a little funky but OK for our purposes. We don't have a statically typed array we're serializing, just a polymorphic array that will end up in JSON.
      queries << error_string
      self.set_queries(queries)
    end

    def self.get_queries
      Thread.current[:mysql_tracked_queries]
    end

    def self.listen
      self.set_queries([])
      begin
        yield
      ensure
        self.set_queries(nil)
      end
    end

    def self.set_queries(queries)
      Thread.current[:mysql_tracked_queries] = queries
    end
  end

  ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
    # payload[:result] is not guaranteed to be present (I'm not sure exactly why that is, but a live site incident has informed me)
    sql_query = { "sql" => payload[:sql], "time_taken_seconds" => payload[:result]&.query_time }
    DependencyGraph::SQLQueriesContainer.add_query(sql_query)
  rescue StandardError => e
    # this hook having any errors can interfere with arbitrary parts of our codebase, so we're going to guard against everything and log an error to our container.
    DependencyGraph::SQLQueriesContainer.add_error(e.to_s)
  end

  class SQLQueriesMiddleware
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
      return @app.call(env) unless request.GET.has_key?("dump_sql_queries")

      # query strings break twirp routing
      env["QUERY_STRING"] = "" if env["PATH_INFO"].starts_with?("/twirp/")

      status = headers = body = nil

      DependencyGraph::SQLQueriesContainer.listen do
        status, headers, body = @app.call(env)
        body.close if body.respond_to?(:close)

        body = JSON.pretty_generate(DependencyGraph::SQLQueriesContainer.get_queries)

        headers["Content-Type"] = "application/json"

        # Make sure the actual response has a correct content-length instead
        # of whatever the wrapped app generated.
        headers["Content-Length"] = body.bytesize.to_s
        status = 200
        Rack::Response.new(body, status, headers).finish
      end
    end
  end
end
