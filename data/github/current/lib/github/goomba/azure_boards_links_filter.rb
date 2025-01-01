# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class AzureBoardsLinksFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("a")
    AZURE_BOARDS_LINK_TEXT_PATTERN = /\AAB#(\d+)\z/
    AZURE_BOARDS_LINK_URL_PATTERN = /\/_workitems\/edit\/(\d+)\z/

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:azure_boards_links_in_pr_development_section]
    end

    def self.enabled?(context)
      repo = context[:entity].try(:repository)
      return false unless repo.respond_to?(:owner) && repo.owner.respond_to?(:feature_enabled?) # identification if the entity is a repository to avoid package dependency violation

      repo.owner.feature_enabled?(:azure_boards_links_in_pr_development_section)
    end

    def call(node)
      text_content = node.text_content
      href_content = node["href"]
      return unless text_content && href_content

      text_id_match = text_content.match AZURE_BOARDS_LINK_TEXT_PATTERN
      link_id_match = href_content.match AZURE_BOARDS_LINK_URL_PATTERN
      return unless text_id_match && link_id_match && text_id_match[1].eql?(link_id_match[1])

      result[:links] << AzureBoardsLink.new(node.text_content, node["href"])

      nil
    end
  end

  class AzureBoardsLink
    attr_reader :text, :url

    def initialize(text, url)
      @text = text
      @url = url
    end
  end
end
