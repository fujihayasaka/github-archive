# typed: true
# frozen_string_literal: true

require "faraday"

module Figma
  class APIError < StandardError; end

  class File < T::Struct
    const :key, String
    const :name, String
    const :last_modified, String
    const :thumbnail_url, T.nilable(String)
    const :full_image_url, T.nilable(String)

    # we only work with public Figma files for now
    sig { params(user: User).returns(T::Boolean) }
    def readable_by?(user)
      true
    end

    # just to make the conditional access code happy
    sig { returns(Symbol) }
    def target_for_conditional_access
      # this is an external resource, so no CAP checks are needed
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end

  class Client
    sig { params(access_token: String).void }
    def initialize(access_token)
      @connection = GitHub::FaradayClient::External.new({ url: "https://api.figma.com" }) do |c|
        c.adapter Faraday.default_adapter
        c.headers["X-Figma-Token"] = access_token
      end
    end

    sig { params(item_url: String).returns(Figma::File) }
    def get_file(item_url)
      file_key = extract_file_key_from_url(item_url)
      raise "Invalid Figma URL: could not extract file key" unless file_key

      res = connection.get("/v1/files/#{file_key}")
      raise "Failed to fetch Figma file" unless res.success?

      data = JSON.parse(res.body)
      full_image_url = get_node_image(file_key, item_url, data["thumbnailUrl"])

      File.new(
        key: file_key,
        name: data["name"],
        last_modified: data["lastModified"],
        thumbnail_url: full_image_url,
        full_image_url: full_image_url
      )
    end

    sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
    def extract_file_key_from_url(url)
      return nil unless url

      # Extract file key from URL format: https://www.figma.com/:file_type/:file_key/:file_name
      begin
        uri = URI.parse(url)
        path_parts = (uri.path || "").split("/")

        allowed_hosts = ["figma.com", "www.figma.com"]
        path_parts[2] if allowed_hosts.include?(uri.host) && path_parts.length >= 3
      rescue URI::InvalidURIError
        nil
      end
    end

    private

    sig { params(file_key: String, item_url: T.nilable(String), fallback_url: T.nilable(String)).returns(T.nilable(String)) }
    def get_node_image(file_key, item_url, fallback_url)
      node_id = extract_node_id_from_url(item_url) || "0:1"
      scale = 1

      res = connection.get("/v1/images/#{file_key}?ids=#{node_id}&scale=#{scale}")
      return fallback_url unless res.success?

      data = JSON.parse(res.body)
      return fallback_url if data["err"].present? || !data["images"]&.any?

      data["images"].values.first || fallback_url
    rescue StandardError => e  # rubocop:todo Lint/GenericRescue
      Rails.logger.error("Failed to fetch Figma node image: #{e.message}")
      fallback_url
    end


    sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
    private def extract_node_id_from_url(url)
      return nil unless url

      begin
        uri = URI.parse(url)
        query_params = URI.decode_www_form(uri.query.to_s).to_h
        node_id = query_params["node-id"]
        node_id&.tr("-", ":")
      rescue URI::InvalidURIError
        nil
      end
    end

    sig { returns(GitHub::FaradayClient::External) }
    attr_reader :connection
  end
end
