# typed: true
# frozen_string_literal: true

module GitAuth
  class CommitRefsRequestBody
    attr_reader :json
    def initialize(request_body)
      @json = GitHub::JSON.parse(request_body)
    end

    def path
      path = json["repo_name"]
      unless path.ends_with?(".git")
        path += ".git"
      end
      path
    end

    def repo
      path.to_s.chomp(".git") if path
    end

    def refs
      json["refs"] || []
    end

    def pre_receive_hook_result
      json["pre_receive_hook_result"]["result"]
    end

    def commit_ref_ctx
      json["commit_ref_ctx"]
    end

    def sockstat
      json["sockstat"]
    end

    # See https://github.com/github/babeld/blob/8c6cd3c87fb8a582855519d7b874a56f49e20b45/src/gitauth.c#L795-L807.
    def host_status
      json["host_status"]
    end

    def raw
      json.inspect
    end

    def capabilities
      json.fetch("capabilities", "").strip.split(/\s+/).map do |capa|
        if capa.include? "="
          pair = capa.split("=", 2)
          [pair[0].to_sym, pair[1]]
        else
          [capa.to_sym, true]
        end
      end.to_h
    end
  end
end
