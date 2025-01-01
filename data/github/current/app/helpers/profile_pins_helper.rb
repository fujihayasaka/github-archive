# typed: true
# frozen_string_literal: true

module ProfilePinsHelper
  include BlobHelper

  # Public: Get the URL to an image that's a file in a gist.
  #
  # Returns a String like "https://gist.githubusercontent.com/cheshire137/e85204895f59dfc3a002d54191307c9d/raw/bd01533989683b791002b8d03d2da9749edfb557/cheshireface.png".
  def gist_image_url(gist, gist_file)
    build_raw_url(type: :gist, route_options: {
      # since proxima doesn't support gists we're safe to use .login directly here
      user_id: gist.owner&.login || Gist::ANONYMOUS_USERNAME,
      gist_id: gist.repo_name,
      sha: gist.sha,
      file: gist_file.name,
    })
  end

  def encoded_name_for(gist_file)
    if (name = gist_file.name).present?
      Addressable::URI.encode_component(name, Addressable::URI::CharacterClasses::PATH)
    end
  end
end
