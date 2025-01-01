# typed: false
# frozen_string_literal: true

module RepositoryActionHelper
  include SvgHelper

  def render_sidebar_documentation
    GitHub::Goomba::MarkdownPipeline.to_html(RepositoryActions::Onboarding::SidebarDocs::CONTENT)
  end

  def instrument_actions_page_view(workflow_run_count: 0, actions_count: 0)
    return unless logged_in?
    payload = {
      repository_id: current_repository.id,
      actor_id: current_user.id,
      workflows_displayed_count: workflow_run_count,
      actions_displayed_count: actions_count,
      url: request.url,
    }

    GitHub.instrument("actions.index_page_view", payload)
  end

  def instrument_actions_onboarding_page_view
    return unless logged_in?
    payload = {
      repository_id: current_repository.id,
      actor_id: current_user.id,
      url: request.url,
    }

    GitHub.instrument("repository_actions.onboarding_page_view", payload)
  end

  def instrument_actions_onboarding_filter_page_view
    return unless logged_in?
    payload = {
      repository_id: current_repository.id,
      actor_id: current_user.id,
      url: request.url,
    }
    GitHub.instrument("repository_actions.onboarding_filter_page_view", payload)
  end

  # The `owner` option has been added specifically so that we can render the
  # Google, AWS, and Azure icons. The assumption here is that their SVG files
  # are named the same way their GitHub org is.
  def action_icon(name:, icon_name: nil, color: "FFFFFF", title: nil, size: nil, owner: nil)
    folder = "feather"

    if owner && RepositoryActions::ActionPartners::CUSTOM_ICON_PARTNERS.include?(owner.downcase)
      folder = "icons/actions"
      icon_name = owner.downcase
      size = "50%"
    end

    # If the icon name is nil or "play", we want to add a margin to the left
    if icon_name.nil? || icon_name == "play"
      options = { style: "color: ##{ color }; margin-left: 10%;" }
      icon_name = "play"
    else
      options = { style: "color: ##{ color };" }
    end

    options[:title] = title || icon_name
    options[:size] = size if size.present?

    svg("#{folder}/#{icon_name}.svg", options)
  end

  # Adds or removes fullscreen query param from the URL.
  def fullscreen_param_url(url, fullscreen: true)
    url = Addressable::URI.parse(url)

    if fullscreen
      url.query_values = (url.query_values || {}).merge({ "fullscreen" => fullscreen.to_s })
    else
      url.query_values = (url.query_values || {}).except("fullscreen")
    end

    url.to_s
  end
end
