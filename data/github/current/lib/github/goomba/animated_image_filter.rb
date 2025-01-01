# typed: true
# frozen_string_literal: true

require "css_parser"

module GitHub::Goomba
  # This filter wraps <img> tags that point to GIFs into a player element
  # which can responsively react to the viewers preference whether to reduce
  # motion on the page.
  #
  # We need to do this server-side because Alambic serves uploaded files using
  # opaque, extension-less names, requiring us to check the mime type (stored
  # upon upload).
  #
  # For non-Alambic (external) images, we just check the extension
  # (anything else would be too costly). This part could be done on the client,
  # but consolidating it here simplifies the client-side code and allows easier
  # expansion into other autoplayable file formats that we want to support.
  #
  # This filter MUST come BEFORE CamoFilter (or any filters that renames src).
  class AnimatedImageFilter < NodeFilter
    # Need to match all <a>'s in addition to <img>'s, because `a:has(> img:only-child)` is not supported
    SELECTOR = Goomba::Selector.new("img")

    def selector
      SELECTOR
    end

    def self.enabled?(context)
      return true if context[:entity]&.is_a?(Repository)
      return true if context[:gist]
      return true if context[:subject]&.is_a?(GistComment)
      return true if context[:subject]&.is_a?(DiscussionPost) || context[:subject]&.is_a?(DiscussionPostReply)
      return true if context[:page]&.is_a?(GitHub::Unsullied::Page)
      false
    end

    # input: <img src="">
    # output:
    #         <img data-animated-image src="">
    def call(element)

      begin
        uri = Addressable::URI.parse(element["src"])
        return element unless uri.present?   # no (or empty) src attribute
      rescue Addressable::URI::InvalidURIError
        return element                       # src is invalid
      end

      begin
        origin = uri.origin
      rescue ArgumentError
        return element # the origin contains invalid characters
      end

      wrap = false
      if uri.path.downcase.ends_with?(".gif")
        wrap = true # src is an external link to what seems to be a gif
      elsif origin == GitHub.alambic_assets_host || secure_asset_img?(element)
        guid = uri.path.split("/").last
        if UserAsset.find_by(guid: guid)&.content_type == "image/gif"
          wrap = true # src is a gif uploaded to Alambic
        end
      elsif extract_content_type_secured_asset(element) == "image/gif"
        wrap = true
      end

      return element unless wrap

      element["data-animated-image"] = ""
      element
    end

    private

    def secure_asset_img?(element)
      element["class"]&.split(" ")&.include?("js-img-time")
    end

    def extract_content_type_secured_asset(element)
      content_type = element["content-type-secured-asset"]
      return "" unless content_type
      element.remove_attribute("content-type-secured-asset")
      content_type
    end
  end
end
