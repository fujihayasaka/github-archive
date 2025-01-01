# typed: strict
# frozen_string_literal: true

module FundingLinksHelper
  extend T::Helpers
  extend T::Sig
  include ActionView::Helpers::AssetTagHelper
  include HydroHelper
  include OcticonsHelper

  sig { params(platform: T.any(String, Symbol), size: Integer).returns(String) }
  def funding_platform_icon(platform, size: 16)
    if platform.to_s == "custom"
      octicon("link", class: "color-fg-muted", alt: platform)
    else
      path = "modules/site/icons/funding_platforms/#{platform}.svg"
      image_tag(path, width: size, height: size, class: "octicon rounded-2 d-block", alt: platform)
    end
  end

  sig do
    params(name: T.any(String, Symbol), url_or_account: T.untyped, repository: T.nilable(Repository)).returns(String)
  end
  def funding_link(name, url_or_account, repository:)
    platform = FundingPlatforms.find(name)
    analytics_attrs = funding_links_attrs(name, url_or_account, repository: repository)
    link_options = { target: "_blank" }.merge(data: analytics_attrs)

    if url = platform.url
      account = url_or_account
      content_tag(:a, link_options.merge(href: "#{url}#{account}")) do
        content_tag(:span) do
          safe_join(["#{url.host}#{url.path}", content_tag(:strong, account)])
        end
      end
    else
      url = url_or_account
      safe_link_to(url, url, link_options)
    end
  end

  sig { params(repository: T.nilable(Repository)).returns(T::Hash[String, T.untyped]) }
  def funding_button_attrs(repository:)
    current_user = T.let(T.unsafe(self).current_user, T.nilable(User))
    hydro_click_tracking_attributes(
      "sponsors.repo_funding_links_button_click",
      platforms: repository&.funding_links_to_hydro,
      repo_id: repository&.id,
      owner_id: repository&.owner_id,
      user_id: current_user&.id,
      is_mobile: false)
  end

  sig do
    params(
      platform_name: T.any(String, Symbol),
      account: String,
      repository: T.nilable(Repository)
    ).returns(T::Hash[String, T.untyped])
  end
  def funding_links_attrs(platform_name, account, repository:)
    platform = FundingPlatforms.find(platform_name)
    current_user = T.let(T.unsafe(self).current_user, T.nilable(User))

    hydro_attributes = hydro_click_tracking_attributes(
      "sponsors.repo_funding_links_link_click",
      platform: FundingPlatforms.to_hydro(platform, account),
      platforms: repository&.funding_links_to_hydro,
      repo_id: repository&.id,
      owner_id: repository&.owner_id,
      user_id: current_user&.id,
    )

    { "ga-click" => "Dashboard, click, Nav menu - item:org-profile context:organization" }.merge(hydro_attributes)
  end

  # Public: The path to the global preferred funding file for a specified repository.
  #
  # repository - The Repository to get the preferred funding file path for.
  sig { params(repository: Repository).returns(T.nilable(String)) }
  def global_preferred_funding_path(repository)
    return unless global_funding = repository.preferred_files.fetch(:funding, global: true)

    global_funding.permalink
  end
end
