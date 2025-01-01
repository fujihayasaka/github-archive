require "blob_operations/spokes/client"

module Spokes
  def self.client
    @client ||= BlobOperations::Spokes::Client.new
  end

  def self.ca_file_path
    "#{Rails.root}/certs/spokes.pem"
  end

  def self.client_key_path
    "#{Rails.root}/certs/spokes.key"
  end

  def self.client_cert_path
    "#{Rails.root}/certs/spokes.crt"
  end

  def self.certs
    return unless File.exist?(self.ca_file_path)

    {
      ca_file: ::Spokes.ca_file_path,
      client_key: ::Spokes.client_key_path,
      client_cert: ::Spokes.client_cert_path
    }
  end
end

ca_file = ENV["SPOKES_CA_FILE"]
if ca_file.present?
  File.write(Spokes.ca_file_path, ca_file)
end

client_key = ENV["SPOKES_CLIENT_KEY"]
if client_key.present?
  File.write(Spokes.client_key_path, client_key)
end

client_cert = ENV["SPOKES_CLIENT_CERT"]
if client_cert.present?
  File.write(Spokes.client_cert_path, client_cert)
end
