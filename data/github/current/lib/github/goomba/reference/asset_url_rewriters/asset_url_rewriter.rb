# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference::AssetUrlRewriters
  DEFAULT_IMAGE_EXPIRATION_TIME = 5.minutes

  # All User Assets are now unified under a new URL format
  NEW_URL_PATTERN = %r{\/user-attachments\/assets\/[0-9a-fA-F\-]+(\/)?$}

  class AssetUrlRewriter
    def initialize(url_pattern, for_email, is_node_authorized)
      @url_pattern = url_pattern
      @for_email = for_email
      @is_node_authorized = is_node_authorized
    end

    def call(node, asset)
      process(node, asset)
    end

    def rewrite_url(asset)
      raise NotImplementedError
    end

    private

    def process(node, asset)
      asset_node = node.select("img, video").first

      # Return node without html wrapper tags if the asset node is not an image or video element.
      # This also returns if asset is not HTML safe
      return node.children.first if asset_node.nil?

      # Return unmodified node if the user is not authorized to view the asset
      return Goomba::DocumentFragment.new(node.inner_html) unless @is_node_authorized

      asset_node_src = asset_node["src"]

      # return the asset_node without signing so that image renders don't look broken
      return ActionController::Base.helpers.content_tag("a", "#{asset.name} (view on web)", href: asset_node_src) if @for_email

      url_matches = asset_node_src.match(NEW_URL_PATTERN)
      url_matches ||= asset_node_src.match(@url_pattern)

      # Return unmodified node if URL does not match a GitHub canonical asset URL
      return Goomba::DocumentFragment.new(node.inner_html) unless url_matches

      # Rewrite canoncial URL to include signed JWT URL
      rewritten_url = rewrite_url(asset)

      # If no rewrites happen return unmodified node
      return asset_node if rewritten_url.blank?

      # add src attribute to the node for image and video tags
      asset_node["src"] = rewritten_url

      # add data-canonical-src attribute to the node for video tags since the
      # player partial uses this attribute to set the video source

      if asset.video_content?
        asset_node["data-canonical-src"] = rewritten_url
      elsif asset.image_content? || asset.svg_content?
        if asset_node.parent.present? && asset_node.parent.tag == :a
          asset_node = asset_node.parent
          asset_node["href"] = rewritten_url
        end
      end

      Goomba::DocumentFragment.new(node.inner_html)
    end
  end
end
