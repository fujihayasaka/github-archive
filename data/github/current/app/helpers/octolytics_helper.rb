# typed: false
# frozen_string_literal: true

module OctolyticsHelper
  # Public: Generate the "global" octolytics meta tags.
  def octolytics_meta_tag
    return "" unless octolytics_enabled?

    actor = if logged_in?
      tag(:meta, name: "octolytics-actor-id",     content: current_user.id) <<
      tag(:meta, name: "octolytics-actor-login",  content: current_user.display_login) <<
      tag(:meta, name: "octolytics-actor-hash",   content: OpenSSL::HMAC.hexdigest("sha256", octolytics_secret, current_user.id.to_s))
    else
      ""
    end

    tag(:meta, name: "octolytics-url", content: "#{GitHub.collector_public_url}/github/collect") <<
    actor
  end

  # Public: Generate octolytics dimension data for a repository.
  def octolytics_repository_tags(repository)
    return "" unless octolytics_enabled?
    return "" unless repository
    html = []
    html << octolytics_user_tags(repository.owner)
    html << tag(:meta, name: "octolytics-dimension-repository_id", content: repository.id)
    html << tag(:meta, name: "octolytics-dimension-repository_nwo", content: repository.name_with_display_owner)
    html << tag(:meta, name: "octolytics-dimension-repository_public", content: repository.public?)
    html << tag(:meta, name: "octolytics-dimension-repository_is_fork", content: repository.fork?)
    if repository.fork? && repository.parent
      html << tag(:meta, name: "octolytics-dimension-repository_parent_id", content: repository.parent.id)
      html << tag(:meta, name: "octolytics-dimension-repository_parent_nwo", content: repository.parent.name_with_display_owner)
    end
    if root = repository.root
      html << tag(:meta, name: "octolytics-dimension-repository_network_root_id", content: root.id)
      html << tag(:meta, name: "octolytics-dimension-repository_network_root_nwo", content: root.name_with_display_owner)
    end
    safe_join(html)
  end

  # Public: Generate octolytics dimension data for a user.
  def octolytics_user_tags(user)
    return "" unless octolytics_enabled?
    return "" unless user
    tag(:meta, name: "octolytics-dimension-user_id",       content: user.id) <<
    tag(:meta, name: "octolytics-dimension-user_login",    content: user.display_login)
  end

  # Internal: Determines appropriage Octolytics secret to use for analytics depending on
  # if we are serving GitHub or Gist.
  def octolytics_secret
    if serving_gist_standalone?
      GitHub.gist_octolytics_secret
    else
      GitHub.octolytics_secret
    end
  end

  def octolytics_enabled?
    GitHub.octolytics_enabled?
  end
end
