# typed: true
# frozen_string_literal: true

module GitHub
  module Pages
    class EnterpriseBuilderApiClient

      def endpoint
        return @endpoint if @endpoint
        @endpoint = "http://localhost:9097"
      end

      def client
        return @client if defined?(@client)
        if GitHub.pages_builds_hmac_key.empty?
          @client = Faraday.new(url: endpoint)
        else
          @client = Faraday.new(url: endpoint) do |conn|
            conn.use GitHub::FaradayMiddleware::RequestID
            conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.pages_builds_hmac_key
            conn.adapter :persistent_excon
            conn.request :retry, max: 3
          end
        end
      end

      # Calling page build api on enterprise server
      def page_build(clone_url, branch, source_dir, build_path, environment)
        if source_dir.nil?
          source_dir = "/"
        end
        res = client.post do |req|
          req.url "/build"
          req.options["timeout"] = page_build_timeout.minutes.to_i
          req.headers["Content-Type"] = "application/json"
          req.body = {
            clone_url: clone_url,
            branch: branch,
            directory: source_dir,
            build_path: build_path,
            environment: environment
          }.to_json
        end
        parse_response(res.body)
      end

      # Calling page clean api on enterprise server to clean folder
      def page_clean(path)
        res = client.post do |req|
          req.url "/clean"
          req.options["timeout"] = 1.minute.to_i
          req.headers["Content-Type"] = "application/json"
          req.body = {
            path: path
          }.to_json
        end
        parse_response(res.body)
      end

      # Calling page sync api on enterprise server to sync generated pages file
      def page_sync(build_path, destination, environment)
        res = client.post do |req|
          req.url "/sync"
          req.options["timeout"] = page_sync_timeout.minutes.to_i
          req.headers["Content-Type"] = "application/json"
          req.body = {
            build_path: build_path,
            destination: destination,
            environment: environment
          }.to_json
        end
        parse_response(res.body)
      end

      # Check if page build is healthy
      def page_build_available?
        res = client.get do |req|
          req.url "/health"
        end
        res.status == 200
      end

      private

      def parse_response(response)
        result = JSON.parse(response)
        status = result.key?("status") ? result["status"] : 0
        err = result.key?("err") ? result["err"] : nil
        out = result.key?("out") ? result["out"] : nil
        commit = result.key?("commit") ? result["commit"] : nil
        BuildStatusObject::new(status, err, out, commit)
      end

      def page_build_timeout
        timeout = ENV["ENTERPRISE_PAGES_BUILD_TIMEOUT_MINUTES"].to_i
        if timeout > 0
          timeout
        else
          11
        end
      end

      def page_sync_timeout
        timeout = ENV["ENTERPRISE_PAGES_SYNC_TIMEOUT_MINUTES"].to_i
        if timeout > 0
          timeout
        else
          10
        end
      end
    end
  end
end
