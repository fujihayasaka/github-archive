# typed: false
# frozen_string_literal: true

module GistsHelper
  OG_IMAGE_FILE_NAMES = [
    "og_image.png",
    "og_image.jpg",
    "og_image.jpeg",
    "og_image.gif",
  ]

  def share_and_clone_data_attributes(gist, type)
    feature_clicked = case type
    when :share
      RepositoriesHelper::CloneDownloadClick::FeatureClicked::SHARE
    when :embed
      RepositoriesHelper::CloneDownloadClick::FeatureClicked::EMBED
    when :http # also used for https
      RepositoriesHelper::CloneDownloadClick::FeatureClicked::USE_HTTPS
    when :ssh
      RepositoriesHelper::CloneDownloadClick::FeatureClicked::USE_SSH
    when :gh_cli
      RepositoriesHelper::CloneDownloadClick::FeatureClicked::USE_GH_CLI
    end
    return {} unless feature_clicked

    clone_download_click_attributes(git_repo: gist, feature_clicked: feature_clicked)
  end

  # Public: Determine which icon symbol to show for the gist.
  #
  # gist - The Gist to render an icon for
  #
  # Returns a String.
  def gist_type_symbol(gist)
    @gist_type_symbol ||= gist_type_symbol!(gist)
  end

  def gist_type_symbol!(gist)
    if gist.fork? && gist.parent
      "repo-forked"
    else
      gist.public? ? "code-square" : "lock"
    end
  end

  # What host is Gist on?
  def gist_host_name
    if GitHub.gist3_domain?
      GitHub.gist3_host_name
    else
      GitHub.gist_host_name
    end
  end

  def gist_root_url
    if GitHub.gist3_domain?
      new_gist_url(host: GitHub.gist3_host_name)
    else
      new_gist_url
    end
  end

  def my_gists_url
    if GitHub.gist3_domain?
      my_gist_listings_url(host: GitHub.gist3_host_name)
    else
      my_gist_listings_url
    end
  end

  def gist_embed_stylesheet_url
    # gists_helper does not have access to `current_user`.
    asset_bundle = AssetBundles.new
    filename = asset_bundle.expand_bundle_name("gist-embed.css")
    base = GitHub.asset_host_url.presence || base_url
    File.join(base, "assets", filename)
  end

  def anonymous_gist_avatar(size = 30, options = {})
    options[:class] = options[:class].to_s + " avatar-user"

    image_tag "gravatars/gravatar-user-420.png",
      options.reverse_merge({
        width: size,
        height: size,
        alt: "anonymous",
      })
  end

  def gist_open_graph_image_file(gist)
    return nil if gist.files.size == 0

    # Return the file named og_image
    gist.files.each do |gist_file|
      return gist_file if gist_file.image? && OG_IMAGE_FILE_NAMES.include?(gist_file.name.downcase)
    end

    # Return the first ima  ge
    gist.files.each do |gist_file|
      return gist_file if gist_file.image?
    end

    nil
  end

  def gist_open_graph_image_url(gist)
    og_image = gist_open_graph_image_file(gist)

    if og_image
      return build_raw_url(type: :gist, route_options: {
        user_id: gist.user_param,
        gist_id: gist.repo_name,
        sha: gist.sha,
        file: og_image.name,
      })
    end

    image_url("modules/gists/gist-og-image.png")
  end

  def is_starred?(gist)
    logged_in? && Stars.domain.gist_starred_by_user?(gist.id, current_user.id)
  end
end
