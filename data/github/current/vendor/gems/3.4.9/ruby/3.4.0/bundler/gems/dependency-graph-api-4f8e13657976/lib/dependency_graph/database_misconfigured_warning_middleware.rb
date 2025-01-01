class DependencyGraph::DatabaseMisconfiguredWarningMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # There's this really weird edge case in rails when a DB connection is fundamentally broken on startup.
    # The app will return blank 500s for everything but no known error handlers are really hit.
    # This check will, when we can tell someone is trying to run dg-api and it's in development mode, try to warn them.
    res = @app.call(env)
    # When this failure mode happens, we end up with a 0 length body and a 500, which is pretty rare.
    if res[0] == 500 && res[2].blank?
      begin
        ActiveRecord::Base.connection.current_database
        ActiveRecord::Migration.check_pending!
      rescue StandardError => ex
        require "rainbow"
        puts Rainbow("Your local development environment doesn't seem to have a functioning dependency_graph_development database! You may need to run script/setup.").red
        raise
      end
    end
    res
  end
end
