# typed: false
# frozen_string_literal: true

class Fastly::Certificate
  ATTRIBUTES = [:customer_id, :certificate_id, :certificate, :certificate_intermediate, :key_file, :offset, :approved].freeze
  attr_accessor *ATTRIBUTES

  # This is a magic number corresponding to sni.github.map.fastly.net.
  # It is used to upload the certificate to the correct set of servers.
  FASTLY_PAGES_HTTPS_OFFSET = 153

  def initialize(params)
    self.offset = FASTLY_PAGES_HTTPS_OFFSET

    ATTRIBUTES.each do |attribute|
      public_send("#{attribute}=", params[attribute]) if params.key?(attribute)
      public_send("#{attribute}=", params[attribute.to_s]) if params.key?(attribute.to_s)
    end
  end

  def self.from_json(body)
    body = JSON.parse(body) if body.is_a?(String)
    body["certificate_id"] ||= body["cert_id"]
    body["certificate"] ||= body["cert"]
    body["certificate_intermediate"] ||= body["cert_intermediate"]
    new(body)
  end

  def to_json(state = nil)
    JSON.generate(to_h, state)
  end

  def to_h
    {
      "cert"              => certificate,
      "cert_intermediate" => certificate_intermediate,
      "key_file"          => key_file,
      "offset"            => offset,
    }
  end
end
