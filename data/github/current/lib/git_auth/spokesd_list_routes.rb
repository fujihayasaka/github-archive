# typed: true
# frozen_string_literal: true

module GitAuth
  # Spokesd ListRoutes call and response.
  # This calls does some git-systems-specific setup for Git requests.
  # It provides routes and extra metadata for the request. The metadata
  # contains a quarantine ID for git pushes, and may contain other data in the
  # future.
  class SpokesdListRoutes
    # Public. Invokes ListRoutes in spokesd and returns a SpokesdListRoutes
    # object with the results.
    def self.fetch(target, protocol, action)
      client =
        case
        when target.wiki?
          target.repository.unsullied_wiki.spokes_api
        else
          target.repository.spokes_api
        end
      resp = client.list_routes(action: action, protocol: protocol)
      new(resp)
    end

    # Private.
    def initialize(resp)
      @resp = resp
    end

    # Public. Returns routes ready to send to babeld.
    #
    # Return value is an array of routes. Each route is [address, path] or
    # [address, path, "noerror"].
    def routes
      @resp.replicas.map { |replica| make_babeld_route(replica) }
    end

    # Public. Returns quarantine ID, if this is a push. If it's set, it should
    # be added to the sockstat.
    def quarantine_id
      @resp.quarantine_id
    end

    private

    def make_babeld_route(replica)
      ip = replica.ip
      # Similar to GitHub::DGit::Route#modify_routes_for_development, we need to add a special case for dgit* routes.
      if (Rails.env.development? || Rails.env.test?) && ip == "" && replica.host_name.start_with?("dgit")
        ip = "localhost"
      end
      route = [ip, replica.absolute_path]
      if replica.route_type == :REPLICA_TYPE_NOERROR
        route << "noerror"
      end
      route
    end
  end
end
