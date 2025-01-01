# typed: true
# frozen_string_literal: true
require "faraday"
require "faraday_middleware"
module GitHub
  class VividCortexApi
    VC_URL = "https://app.vividcortex.com/api/v2/"
    QUERIES_URL = VC_URL + "queries/"
    SAMPLES_URL = QUERIES_URL + "samples"
    HOSTS_URL = VC_URL + "hosts/"
    SECONDS_IN_HOUR = 3600
    SECONDS_IN_TWO_DAYS = 172800
    # the `queries` endpoint of the VividCortex API is very slow if it has to search over all hosts, so we restrict the search to those hosts that can return relevant answers
    # so, if we are only interested in queries to a specific cluster, we use the IDs of hosts in that cluster.
    TAGS = { ApplicationRecord::RepositoriesActionsChecks => "repositories-actions-checks", ApplicationRecord::IssuesPullRequests => "repositories" }

    def self.range_in_seconds
      SECONDS_IN_HOUR
    end

    def self.connection
      @connection ||= Faraday.new(url: VC_URL, request: { timeout: 120 }) do |c|
        c.use Faraday::Request::UrlEncoded
        c.response :json
        c.response :logger
        c.adapter Faraday::default_adapter
        c.authorization(:Bearer, vc_api_token)
      end
    end

    def self.vc_api_token
      return @vc_api_token if defined?(@vc_api_token)

      @vc_api_token = ENV["VC_TOKEN"]
      puts("missing VC_TOKEN environment variable") if @vc_api_token.nil?
      @vc_api_token
    end

    def self.fetch_queries(filter_root, queried_table, hosts)
      page = 0
      offset = 0
      query_list = []
      query_strings = Hash.new
      current_time = Time.now.to_i
      loop do
        retries = 0
        response = T.let(nil, T.untyped)
        ok = T.let(true, T::Boolean)
        loop do
          begin
            response = connection.get(QUERIES_URL, { host: hosts.join(","), from: (current_time - range_in_seconds).to_s, until: current_time.to_s, limit: 50, filter: filter_root + queried_table + "`", offset: offset.to_s })
            ok = true
          rescue Faraday::ServerError => ex
            ok = false
            retries += 1
            puts ex.message
            puts "request failed - server error"
            raise Exception.new("server error from queries endpoint") if retries > 5
          end
          break if ok
        end
        last_id = T.let(0, Integer)
        puts "no response" if response.nil?
        raise Exception.new("queries endpoint returned " + response&.status.to_s) unless response&.status == 200
        queries = response.body["data"]
        query_list.push(*queries)
        queries.each do |q|
          last_id = T.let(q["id"], Integer)
          query_strings[last_id] = q["digest"]
        end
        page += 1
        offset = last_id
        break unless page < 10 # do not fetch more than 500 queries per table
        more_data = response.headers["x-vc-meta-more"]
        break unless more_data
      end
      query_strings
    end

    def self.fetch_samples(query_id)
      # fetch samples for the given query
      # the samples endpoint needs query ids expressed as decimal
      current_time = Time.now.to_i
      start_of_range = current_time - range_in_seconds
      hexid = query_id
      decimal = hexid.to_i(16)
      retries = 0
      response = T.let(nil, T.untyped)
      ok = T.let(true, T::Boolean)
      loop do
        begin
          response = connection.get(SAMPLES_URL, { query: decimal.to_s, from: start_of_range.to_s, until: current_time.to_s })
          ok = true
        rescue Faraday::ServerError => ex
          ok = false
          retries += 1
          puts "retry " + retries.to_s
          puts "request failed - server error"
          raise Exception.new("server error from samples endpoint") if retries > 5
        end
        break if ok
      end
      puts response.status
      raise Exception.new("samples endpoint returned " + response.status.to_s) unless response.status == 200
      samples = response.body
    end

    def self.fetch_hosts_for_domain(domain_class)
      tag = TAGS[domain_class]
      raise Exception.new("No tag defined for domain class " + domain_class.to_s) if tag.nil?
      retries = 0
      response = T.let(nil, T.untyped)
      ok = T.let(true, T::Boolean)
      loop do
        begin
          response = connection.get(HOSTS_URL, { from: -3600, until: 0, nest: "tags" })
          ok = true
        rescue Faraday::ServerError => ex
          ok = false
          retries += 1
          puts "retry " + retries.to_s
          puts "request failed - server error"
          raise Exception.new("server error from hosts endpoint") if retries > 5
        end
        break if ok
      end
      raise Exception.new("hosts endpoint returned " + response.status.to_s) unless response.status == 200
      hosts = []
      all_hosts = response.body["data"]
      all_hosts.each do |h|
        next if h["tags"].nil?
        hosts << h["id"] if h["tags"].include?(tag)
      end
      hosts
    end
  end
end
