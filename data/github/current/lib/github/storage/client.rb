# typed: true
# frozen_string_literal: true

require "faraday"

class GitHub::Storage::Client
  class UnexpectedResponse < ::StandardError; end

  class << self
    attr_writer :default


    delegate :replicate_to, :move_to, :replicate_from, :stats, :delete, :upload, :has_object?, to: :default
  end

  def self.default
    @default ||= new
  end

  def replicate_to(host, oid_map)
    # oid_map maps an oid to the file servers to send it to
    objects = oid_map.map { |m| m.merge!(path_prefix: m[:oid][0]) }

    res = send_request(
      host: host,
      path: "/cluster/replicate/send",
      body: { objects: objects }.to_json,
    )
    response_to_result(res)
  end

  def move_to(host, oid_map)
    # oid_map maps an oid to the file servers to send it to
    objects = oid_map.map { |m| m.merge!(path_prefix: m[:oid][0]) }

    res = send_request(
      host: host,
      path: "/cluster/replicate/move",
      body: { objects: objects }.to_json,
    )
    response_to_result(res)
  end

  # replicate_from instructs the host to copy the oids from any of the nodes that has it
  def replicate_from(host, oids)
    objects = oids.map do |oid|
      {
        oid: oid,
        path_prefix: oid[0],
        fileservers: GitHub::Storage::Allocator.hosts_for_oid(oid),
      }
    end

    res = send_request(
      host: host,
      path: "/cluster/replicate/receive",
      body: { objects: objects }.to_json,
    )
    response_to_result(res)
  end

  def stats(host, partitions)
    res = send_request(
      host: host,
      path: "/cluster/stats",
      body: { partitions: partitions }.to_json,
    )
    response_to_result(res)
  end

  def delete(host, oids)
    objects = oids.map { |oid|  { oid: oid, path_prefix: oid[0] } }

    res = send_request(
      host: host,
      verb: :delete,
      path: "/cluster/replicate/delete",
      body: { objects: objects }.to_json,
    )
    response_to_result(res, [200, 404])
  end

  def upload(host, oid, file)
    res = send_request(
      host: host,
      verb: :put,
      path: "/cluster/replicate/#{oid[0]}/#{oid}",
      body: file,
      headers: { "Content-Type" => "application/octet-stream" },
    )
    response_to_result(res, [201])
  end

  def has_object?(host, oid)
    res = send_request(
      host: host,
      verb: :head,
      path: "/cluster/replicate/#{oid[0]}/#{oid}",
    )

    case res.status
    when 200
      true
    when 404
      false
    else
      raise UnexpectedResponse, "Unexpected status code #{res.status}"
    end
  end

  private

  def send_request(host:, verb: :post, path:, body: "", headers: {})
    url = GitHub.storage_replicate_fmt % host
    conn = Faraday.new(url: url) { |f| build_faraday(f) }
    conn.send(verb) do |req|
      req.url path
      req.body = body
      req.headers["Content-Length"] = req.body.size.to_s
      req.headers["Content-Type"] = "application/json"
      req.headers["Authorization"] = "Token #{token}"
      req.options.timeout = 3000
      req.options.open_timeout = 2
      headers.each { |header, value| req.headers[header] = value }
    end
  end

  def build_faraday(f)
    f.adapter Faraday.default_adapter # make requests with Net::HTTP
  end

  def token
    GitHub.alambic_replication_token
  end

  def response_to_result(res, success = [200])
    body = res.body
    body = "{}" if body.empty?

    [success.include?(res.status), JSON.parse(body)]
  end
end
