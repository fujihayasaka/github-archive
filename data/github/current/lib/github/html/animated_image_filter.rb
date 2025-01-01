# typed: true
# frozen_string_literal: true

module GitHub::HTML
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
  class AnimatedImageFilter < Filter

    def call
      doc.search("img").each do |element|
        modify_element_if_gif(element)
      end

      doc
    end

    # input:  <img src="">
    # output: <img data-animated-image src="">
    def modify_element_if_gif(element)

      begin
        uri = Addressable::URI.parse(element["src"])
        return element unless uri.present?   # no (or empty) src attribute
      rescue Addressable::URI::InvalidURIError
        return element                       # src is invalid
      end
      wrap = false
      if uri.path.downcase.ends_with?(".gif")
        wrap = true # src is an external link to what seems to be a gif
      elsif uri.origin == GitHub.alambic_assets_host || secure_asset_img?(element)
        guid = uri.path.split("/").last
        if UserAsset.find_by(guid: guid)&.content_type == "image/gif"
          wrap = true # src is a gif uploaded to Alambic
        end
      end

      return element unless wrap

      element["data-animated-image"] = ""
      element
    end

    private

    def secure_asset_img?(element)
      element["class"]&.split(" ")&.include?("js-img-time")
    end
  end
end
