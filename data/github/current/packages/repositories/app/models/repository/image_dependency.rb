# typed: true
# frozen_string_literal: true

module Repository::ImageDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    has_many :repository_images, -> { order(id: :desc) }, dependent: :destroy
    has_one :open_graph_image, -> { T.unsafe(self).open_graph }, class_name: "RepositoryImage", inverse_of: :repository
  end

  # Public: Whether this repository has a custom image to use with Open Graph as opposed to being
  # represented by the owner's avatar.
  #
  # Returns a Promise resolving to a Boolean.
  def async_uses_custom_open_graph_image?
    if public?
      async_open_graph_image.then { |image| image.present? }
    else
      Promise.resolve(false)
    end
  end

  # Public: Whether this repository has a custom image to use with Open Graph, but
  # synchronously.
  #
  # Returns a Boolean.
  def uses_custom_open_graph_image?
    public? && open_graph_image.present?
  end

  # Public: Returnes the URL from the enhanced GitHub open graph service.
  #
  # Returns a String.
  def og_image_url
    OpenGraph.new(self).og_image_url
  end

  def show_enhanced_og_image?
    return false if GitHub.enterprise?
    return false if private?
    return false if owner&.organization? && T.cast(owner, Organization).ip_allowlist_enabled?
    true
  end

  def async_open_graph_image_url(viewer:)
    get_user_avatar = -> do
      size = 400
      async_owner.then do |owner|
        if owner
          owner.primary_avatar_url(size)
        else
          User.ghost.primary_avatar_url(size)
        end
      end
    end

    if private?
      get_user_avatar.call
    else
      async_open_graph_image.then do |image|
        if image
          image.storage_external_url(viewer)
        elsif owner && show_enhanced_og_image?
          og_image_url
        else
          get_user_avatar.call
        end
      end
    end
  end

  # Public: Return the URL of the Open Graph image set for this repository if
  # it's public and a custom image has been provided, or nil otherwise.
  #
  # Returns a URL String or nil.
  def custom_open_graph_image_url(user)
    return nil if private?

    image = open_graph_image
    return nil if image.nil?

    image.storage_external_url(user)
  end

  # Public: Return the URL of the Open Graph image associated with this
  # repository, falling back to the owner's avatar otherwise.
  def open_graph_image_url(user)
    custom_open_graph_image_url(user) || begin
      (owner || User.ghost).primary_avatar_url(400)
    end
  end
end
