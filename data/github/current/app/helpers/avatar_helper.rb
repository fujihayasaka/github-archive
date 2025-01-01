# typed: true
# frozen_string_literal: true

# All our frontend avatar methods. All of them.
module AvatarHelper
  CACHE_VERSION = 3

  include PlatformHelper
  include HovercardHelper

  TagHelper = T.type_alias { ActionView::Helpers::TagHelper }

  # Create an img tag to display the avatar for a user/org/business.
  #
  # The image is always 140px so the browser will only make one request per
  # user and cache it. The size parameter must not be set over 70 pixels to
  # accomodate @2x retina displays.
  #
  # owner   - A User, Organization, or Business. If you want to generate an actual gravatar
  #           for an email use `gravatar_for_email`.
  # size    - An optional Integer pixel size to display the image at
  #           (default: 30, max: 70). This is *not* the size of the
  #           avatar, which is always 140.
  # options - An optional Hash passed through to the rails `tag` helper.
  #
  # Examples
  #
  #   avatar_for(current_user, 48, :class => :avatar)
  #   # => '<img height="48" width="48" class="avatar" src="https://avatars.github.com . . .">'
  #
  # Returns an img tag String.
  def avatar_for(owner, size = 30, options = {})
    # Don't want to support nil but some methods are still passing it. In Gist nil is a valid option,
    # given anonymous gists.
    owner ||= User.ghost

    unless owner.try(:can_be_avatar_owner?)
      error = "Expected base type #{Avatar.valid_owner_type_sentence}, got #{owner.class}"
      raise(ArgumentError, error)
    end

    options[:src] ||= avatar_url_for(owner, size * 2)
    options[:width] = size
    options[:height] = size
    options[:alt] ||= alt_text(owner)

    options[:class] = options[:class].to_s + " avatar-user" if avatar_user_actor?(owner)

    T.cast(self, TagHelper).tag(:img, options)
  end

  def avatar_component_options(owner, size = 30)
    {
      src: avatar_url_for(owner, size * 2),
      alt: alt_text(owner),
      shape: avatar_user_actor?(owner) ? :circle : :square
    }
  end

  def avatar_user_actor?(actor)
    actor.class == User || actor.is_a?(PlatformTypes::User) || (actor.respond_to?(:user?) && actor.user?)
  end

  def avatar_class_names(actor)
    if avatar_user_actor?(actor)
      "avatar avatar-user"
    else
      "avatar"
    end
  end

  def alt_text(owner)
    case owner
    when User then owner.bot? ? "@#{owner.name}" : "@#{owner.display_login}"
    when OauthApplication then owner.name
    when Marketplace::Listing then owner.name
    when Team then "@#{owner.combined_slug}"
    when Business then owner.name
    else
      if owner.respond_to?(:login)
        "@#{owner.login}"
      else
        "avatar image"
      end
    end
  end

  # Deprecated: Use `avatar_for` with a User instead unless you really
  # want an actual honest to goodness gravatar and not just a user's avatar.
  #
  # Like `avatar_for` but accepts a String email rather than a User.
  def gravatar_for_email(email, size = 30, options = {})
    options[:width] = size
    options[:height] = size
    options[:alt] ||= ""
    options[:class] = options[:class].to_s + " avatar-user"

    if GitHub.gravatar_enabled? && email.present?
      raise ArgumentError, "Expected String email, got #{email.class}" unless email.is_a?(String)
      # Proxy all gravatar images through Camo so we can remove gravatar/wordpress
      # URLs from our CSP `img-src` directive
      options[:src] = gravatar_url_for(email, 140, proxied: true)
      options[:data] = { canonical_src: gravatar_url_for(email, 140) }
    else
      options[:src] = gravatar_disabled_image
    end

    T.cast(self, TagHelper).tag(:img, options)
  end

  # Public: Create an avatar linked to a user's page.
  #
  # user - A User or Organization.
  # size - An Integer dimension in pixels. Default is 40.
  # responsive_hidden - A boolean to indicate if this avatar should be responsively hidden on smaller viewports. Defaults to false.
  #
  # Returns a String.
  def timeline_comment_avatar_for(user:, size: 40, responsive_hidden: false)
    T.cast(self, TagHelper).content_tag :span, class: "timeline-comment-avatar #{"d-none d-md-block" if responsive_hidden}" do
      T.cast(self, ApplicationHelper).linked_avatar_for(user, size, img_class: "avatar")
    end
  end

  # Create an img tag to display the user's large avatar.
  #
  # Big avatars should be used very rarely (profile page) and the
  # `avatar_for` method should generally be used rather than this method.
  #
  # user    - User whose avatar you want to display
  # options - An optional Hash passed through to the rails `tag` helper.
  #
  # Examples
  #
  #   profile_avatar_for(current_user, :class => :avatar)
  #   # => '<img height="200" width="200" class="avatar" src="https://avatar.github.com . . .">'
  #
  # Returns an img tag String.
  def profile_avatar_for(user, options = {})
    size = options[:size] || 230
    profile_avatar_using(avatar_url_for(user, size * 2), options)
  end

  # Create an img tag to display the given avatar URL.
  #
  # image_url - URL to the avatar to display
  # options - optional Hash with Rails helper options, including:
  #   :size
  #   :alt
  #   :class
  #
  # Returns an img tag String.
  def profile_avatar_using(image_url, options = {})
    size = options.delete(:size) || 230
    options[:alt] ||= ""
    classes = "avatar #{options.delete(:class)}".strip
    T.cast(self, TagHelper).tag(:img, options.merge(src: image_url.to_s, width: size, height: size, class: classes))
  end

  # Produces an appropriately sized avatar URL with a fallback image for a user.
  #
  # user  - User whose avatar you want to display. Can optionally be an email
  #         or object that responds to #gravatar_id for legacy purposes.
  # size  - An optional Integer which determines the size of the
  #         image. Defaults to 60.
  #
  # Returns a String.
  def avatar_url_for(user, size = 60)
    user.primary_avatar_url(size)
  end

  # Produces an appropriately sized gravatar URL with a fallback image for an email.
  #
  # email         - Email whose Gravatar you want to display.
  # size          - An optional Integer which determines the size of the
  #                 image. Defaults to 30.
  # default_image - An optional String which determines the default image to
  #                 show in the case that no Gravatar is associated with the
  #                 provided email.
  # proxied       - Whether the returned URL should be proxied through our image proxy service.
  #                 Use this if the URL is going to be used to insert an img tag, otherwise
  #                 our Content Security Policy will block the image.
  #
  # Returns a String.
  def gravatar_url_for(email, size = 30, default_image = "gravatar-user-420", proxied: false)
    url = User::AvatarList.gravatar_url_for(email, size, default: default_image)
    if proxied
      GitHub::HTML::CamoFilter.asset_proxy_url(url)
    else
      url
    end
  end

  # Insert a linked gravatar for a commit author or committer. Linking to the
  # actor's profile page.
  #
  # commit  - A Commit object. When nil, a default gravatar is returned.
  # type    - Either :author or :committer.
  # size    - Size of the img in pixels.
  #
  # Returns an <img> tag.
  def linked_avatar_for_commit_actor(commit, type, size, options = {})
    email, user = email_and_user_for_commit_actor(commit, type)

    if user
      actor_rel = T.cast(self, ApplicationHelper).find_rel_type(user, options.delete(:repository))
      T.cast(self, ApplicationHelper).profile_link user, rel: actor_rel, skip_hovercard: options[:skip_hovercard] do
        avatar_for(user, size, options)
      end
    else
      gravatar_for_email(email, size, options)
    end
  end

  def email_and_user_for_commit_actor(commit, type)
    if type != :author && type != :committer
      raise ArgumentError, "type must be :author or :committer"
    end

    email = (commit && commit.__send__("#{type}_email")).to_s
    user = (commit && commit.__send__(type))
    user = T.cast(self, ApplicationHelper).user_for_email(email) if user.nil?

    [email, user]
  end

  # Internal - Default image path when Gravatar is disabled
  #
  # default_image: name of the default image.
  #
  # Returns a path to the image in the frontend server.
  def gravatar_disabled_image(default_image = "gravatar-user-420")
    User::AvatarList.default_image_url(default_image)
  end

  # Public - selects the best worded string based on the
  # owner type of the avatar
  #
  # avatar: an avatar object
  #
  # Returns a string
  def human_avatar_name(avatar)
    case avatar.owner_type
    when "User" then "profile picture"
    when "OauthApplication" then "application logo"
    when "Marketplace::Listing" then "Marketplace listing logo"
    when "RepositoryAction" then "Marketplace Action Avatar"
    when "Team" then "team avatar"
    when "Business" then "enterprise avatar"
    else
      "avatar"
    end
  end

  def direct_avatar_link(path, size = 64)
    PrimaryAvatar.url_for("/#{path}", size: size)
  end
end
