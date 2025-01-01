# typed: true
# frozen_string_literal: true

module DependencyGraph
  # Faraday middleware that inserts a header with the type of user making the request,
  # if that information can be extracted.
  class UserTypeMiddleware < ::Faraday::Middleware
    GITHUB_DEPGRAPH_USER_TYPE_HEADER = "GitHub-DepGraph-User-Type".freeze

    def call(env)
      if actor_type
        env.request_headers[GITHUB_DEPGRAPH_USER_TYPE_HEADER] = actor_type
      end

      @app.call(env)
    end

    private

    # Provide the User record for the current actor
    def actor
      @actor = if !(GitHub.context[:actor_id] || GitHub.context[:actor])
        nil
      elsif GitHub.context[:actor]
        User.find_by_login(GitHub.context[:actor])
      elsif GitHub.context[:actor_id]
        User.find_by(id: GitHub.context[:actor_id])
      end
    end

    # Return a string that represents the type of user making a request,
    # or nil for requests that are not recognized as special.
    # This is passed to the API for it to understand where the traffic is coming from.
    def actor_type
      @actor_type ||= if actor&.bot?
        # In this context, "bot" is an application integration or a programmatic access bot
        # See packages/apps/app/models/botable.rb
        "bot"
      elsif GitHub.robot?(GitHub.context[:user_agent] || "")
        # "robot" in this context is a crawler, defined in
        # lib/github/robots.rb
        "crawler"
      elsif !actor.nil?
        # the actor is logged in, but we don't have a signal they are a bot
        # should be "user" or "organization"
        actor.class.name.demodulize.underscore
      else
        "anonymous"
      end
    end
  end
end
