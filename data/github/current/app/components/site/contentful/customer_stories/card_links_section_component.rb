# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::CardLinksSectionComponent < ApplicationComponent
  include UrlHelper

  def initialize(cards = self.default_cards)
    @cards_data = cards || self.default_cards
    @cards = []
    @themes = %w[indigo blue red pink]
  end

  def default_cards
    ["The ReadME Project", "GitHub Copilot", "Executive Insights"]
  end

  def before_render
    @cards = self.get_links(@cards_data)
  end

  def get_links(cards)
    cards.map { |card| self.card_links(card) }
  end

  # Return a hash of card links based on the card name
  def card_links(card)
    case card
    when "GitHub Copilot"
      {
        heading: "GitHub Copilot",
        body: "AI pair programmer that helps you write code faster.",
        href: features_copilot_path,
        icon: "hubot",
      }
    when "Work at GitHub"
      {
        heading: "Work at GitHub",
        body: "Check out our current job openings.",
        href: "https://github.careers",
        icon: "code-of-conduct",
      }
    when "GitHub Enterprise"
      {
        heading: "GitHub Enterprise",
        body: "Empower your team Transform your business.",
        href: enterprise_marketing_page_path,
        icon: "bookmark",
      }
    when "GitHub Actions"
      {
        heading: "GitHub Actions",
        body: "Automate your workflow from idea to production.",
        href: features_actions_path,
        icon: "zap",
      }
    when "GitHub Advanced Security"
      {
        heading: "GitHub Advanced Security",
        body: "Extra security features available to customers.",
        href: features_security_path,
        icon: "shield-lock",
      }
    when "GitHub Issues"
      {
        heading: "GitHub Issues",
        body: "Project planning for developers.",
        href: features_issues_path,
        icon: "workflow",
      }
    when "Codespaces"
      {
        heading: "Codespaces",
        body: "Blazing fast cloud developer environments.",
        href: features_codespaces_path,
        icon: "code",
      }
    when "Executive Insights"
      {
        heading: "Executive Insights",
        body: "Get expert perspectives. Stay ahead with insights from industry leaders.",
        href: "https://github.com/solutions/executive-insights",
        icon: "briefcase",
      }
    else
      {
        heading: "The ReadME Project",
        body: "Stories and voices from the developer community.",
        href: readme_index_path,
        icon: "book",
      }
    end
  end
end
