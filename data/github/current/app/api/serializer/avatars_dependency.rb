# typed: true
# frozen_string_literal: true

module Api::Serializer::AvatarsDependency
  def avatar(user, size = nil)
    u = user.primary_avatar_url(size)
    u += "?" unless u["?"]
    u # lets people append "size=140" to the url
  end

  # TODO: avatar-urls feature flag.
  def event_avatar_url(user_id, org = false)
    "#{GitHub.alambic_avatar_url}/u/#{user_id}?"
  end

  def avatar_url(gravatar_id, org = false, size = nil)
    default_image = org ? "gravatar-org-420" : "gravatar-user-420"
    avatars = User::AvatarList.with_gravatar_id(gravatar_id)
    strip_gravatar_subdomain(avatars.gravatar_url(size, default_image))
  end

  def strip_gravatar_subdomain(url)
    url.sub %r(\Ahttps://\d.gravatar.com), "https://gravatar.com"
  end
end
