# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class SecureAssetsURLFilter < NodeFilter
    SELECTOR   = Goomba::Selector.new("img[src*='github.localhost'], img[src*='githubusercontent.com']")
    GUID_REGEX = /(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}/

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:secure_user_assets]
    end

    def self.enabled?(context)
      if context[:entity].is_a?(Repository)
        return GitHub.flipper[:secure_user_assets].enabled?(context[:entity].owner)
      elsif context[:organization].is_a?(Organization)
        return GitHub.flipper[:secure_user_assets].enabled?(context[:organization])
      end

      false
    end

    def call(element)
      begin
        uri = Addressable::URI.parse(element["src"])
        return element unless uri.present?   # no (or empty) src attribute
      rescue Addressable::URI::InvalidURIError
        return element                       # src is invalid
      end

      return element unless uri.host.present?

      # In development, assets are served under `/storage/user/:user_id/files/:guid`. In production, they are served
      # under the `user-images` subdomain. We just want to rewrite uri's if one of the cases are true.
      #
      # Examples:
      #
      #   Development:
      #     - Before: http://alambic.github.localhost:52829/storage/user/2/files/f2345a7f-5ded-440e-a58a-81479b1019f8
      #     - After:  http://github.localhost:52829/assets/storage/user/2/files/f2345a7f-5ded-440e-a58a-81479b1019f8
      #
      #   Production:
      #     - Before: https://user-images.githubusercontent.com/1/16914-87825ddf-8d18-487c-a778-d901d94f2f0c.png
      #     - After:  https://github.com/assets/1/16914-8d18-487c-a778-d901d94f2f0c
      if (uri.host.match?(/github\.localhost/) && uri.request_uri.match?(/\/storage\/user/)) || is_user_images?(uri.host)
        request_uri = "/assets#{uri.request_uri}"

        # On production, the request's url is actually the key for the asset on S3 (e.g. 1/16914-87825ddf-8d18-487c-a778-d901d94f2f0c.png)
        # The second part of the resquest's uri represents the assets's id (16914) + guid (87825ddf-8d18-487c-a778-d901d94f2f0c)
        # and we need to extract the guid from that section.
        if is_user_images?(uri.host)
          parts = uri.request_uri.gsub(/\A\//, "").split("/")
          request_uri = "/assets/#{parts[0]}/#{uri.request_uri.match(GUID_REGEX)}"
        end

        uri.request_uri = request_uri

        host, port = GitHub.host_name.split(":")
        uri.host = host
        if port.present?
          uri.port = port
        end

        # add metric tracking selector
        if element["class"]
          element["class"] << " js-img-time"
        else
          element["class"] = "js-img-time"
        end

        element["src"] = uri.to_s
        element
      end
    end

    private

    def is_user_images?(host)
      host.match?(/user-images\.githubusercontent\.com/)
    end
  end
end
