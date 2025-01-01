# typed: true
# frozen_string_literal: true

module Api::Serializer::ActionsRunnerApplicationsDependency
  # Creates a hash to be serialized to JSON
  #
  # download - Must be a hash with os, architecture, download_url and filename keys
  #
  def actions_runner_applications_hash(data, options = {})

    data[:downloads] ||= []
    data[:downloads].map do |download|
      download_runner_application_hash(download)
    end
  end

  def download_runner_application_hash(download)
    {
      os: download.os,
      architecture: download.architecture,
      download_url: download.download_url,
      filename: download.filename
    }.tap do |hash|
      hash[:temp_download_token] = download.download_token unless download.download_token.blank?
      hash[:sha256_checksum] = download.sha256_hash unless download.sha256_hash.blank?
    end
  end
end
