# typed: true
# frozen_string_literal: true

class Api::Feeds < Api::App

  # EXPERIMENTAL
  get "/feeds", operation_id: "activity/get-feeds" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    timeline_href               = html_url "/timeline"
    user_href                   = html_url "/{user}"
    security_advisories_href    = html_url "/security-advisories"
    repository_discussions_href = html_url "/{user}/{repo}/discussions"
    repository_discussions_category_href = html_url "/{user}/{repo}/discussions/categories/{category}"

    feeds = {
      timeline_url: timeline_href,
      user_url: user_href,
      repository_discussions_url: repository_discussions_href,
      repository_discussions_category_url: repository_discussions_category_href,
    }
    links = {
      timeline: atom_link(timeline_href),
      user: atom_link(user_href),
      repository_discussions: atom_link(repository_discussions_href),
      repository_discussions_category: atom_link(repository_discussions_category_href),
    }

    # Only real User actors can have a feed
    if logged_in? && current_user.user?
      public_user_href = html_url "/#{current_user.display_login}"
      feeds[:current_user_public_url] = public_user_href
      links[:current_user_public] = atom_link(public_user_href)

      # Don't give out token urls to oauth clients or to personal access tokens
      # with insufficient permissions.
      if current_actor.using_personal_access_token?
        current_user_href, actor_href =
          if access_allowed?(:list_private_repos, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: false)
            [
              html_url("/#{current_user.display_login}.private.atom", auth: true),
              html_url("/#{current_user.display_login}.private.actor.atom", auth: true)
            ]
          end

        org_hrefs =
          if access_allowed?(:get_current_user_org_membership, resource: current_user, member: current_user, allow_integrations: false, allow_user_via_granular_actor: false)
            current_user.organizations.includes(:saml_provider).reject(&:saml_sso_enabled?).map do |org|
              html_url "/organizations/#{org.display_login}/#{current_user.display_login}.private.atom", auth: true
            end
          else
            []
          end

        link_args = {}.tap do |args|
          args[:current_user] = atom_link(current_user_href) if current_user_href.present?
          args[:current_user_actor] = atom_link(actor_href) if actor_href.present?
          args[:current_user_organization] = { href: "", type: "" }
          args[:current_user_organizations] = atom_link(org_hrefs)
        end

        feed_args = {}.tap do |args|
          args[:current_user_url] = current_user_href if current_user_href.present?
          args[:current_user_actor_url] = actor_href if actor_href.present?
          args[:current_user_organization_url] = ""
          args[:current_user_organization_urls] = org_hrefs
        end

        links.update link_args
        feeds.update feed_args
      end
    end

    feeds.update security_advisories_url: security_advisories_href
    links.update security_advisories: atom_link(security_advisories_href)

    feeds[:_links] = links

    deliver_raw feeds
  end

  private

  ATOM = Mime[:atom].to_s

  # Private: Generate an Atom feed link.
  #
  # href - A String url or an Array of String urls.
  #
  # Returns a Hash link or an Array of Hash links.
  def atom_link(href)
    case href
    when Array
      href.map { |h| atom_link h }
    when String
      { href: href, type: ATOM }
    else
      raise ArgumentError
    end
  end
end
