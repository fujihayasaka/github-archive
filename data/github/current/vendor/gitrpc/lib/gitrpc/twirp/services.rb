# typed: true
# frozen_string_literal: true

# This has all the services while we're handling just a few. As these grow it'll
# make sense to split them out into different files like we do for the backend code.

require_relative "../../../proto/spokes.backend_pb"

module GitRPC
  class HealthHandler
    def loadavg(req, env)
      backend = env[:backend]
      avg5, avg10, avg15 = backend.loadavg
      {avg5: avg5, avg10: avg10, avg15: avg15}
    end
  end

  class GitHandler
    def exists(req, env)
      backend = env[:backend]
      return {exists: backend.exist?}
    end

    def read_refs(req, env)
      backend = env[:backend]
      filter =
        case req.filter
        when :DEFAULT
          "default"
        when :EXTENDED
          "extended"
        when :ALL
          "all"
        else
          "default"
        end
      refs = backend.read_refs(filter)
      enc = Array.new
      refs.each { |k, v| enc << Spokes::Backend::Reference.new(refname: k, oid: v) }
      Spokes::Backend::ReadRefsResponse.new(references: enc)
    end
  end
end
