# typed: true
# frozen_string_literal: true

module Site
  module CustomerStoriesHelper
    include ActionView::Helpers::TagHelper, ActionView::Helpers::AssetUrlHelper

    def customer_story_body_cache_key(customer_story_json)
      url, updated_at = customer_story_json.values_at(:url, :updated_at)

      ["site", "customer_stories", url, "customer_story_body", updated_at].join(".")
    end

    def preview_label
      content_tag(:span, "PREVIEW", class: "color-fg-danger text-bold", data: { "test-selector": "customer-stories-preview-label" })
    end

    def customer_story_structured_data_breadcrumb_list_tag(base_url:, url:, name:)
      data = {
        "@context": "http://schema.org",
        "@type": "BreadcrumbList",
        "itemListElement": [
          {
            "@type": "ListItem",
            "position": 1,
            "item": {
              "@id": base_url,
              "name": "Customer Stories"
            }
          },
          {
            "@type": "ListItem",
            "position": 2,
            "item": {
              "@id": url,
              "name": name
            }
          }
        ]
      }

      json = JSON.pretty_generate(data)

      content_tag(:script, json, { type: "application/ld+json" }, false)
    end

    def customer_story_structured_data_article_tag(story)
      article_data = {
        "@context" => "http://schema.org",
        "@type" => "Article",
        "headline" => story[:lead],
        "publisher" => {
          "@type" => "Organization",
          "name" => "GitHub",
          "logo" => image_url("modules/open_graph/github-logo.png")
        },
        "author" => {
          "@type" => "Organization",
          "name" => story[:title],
        }
      }.compact

      if story[:logo].present?
        article_data["author"]["logo"] = story[:logo][:absolute_url]
      end

      images = [story[:hero_image]]

      if images.present?
        article_data["image"] = images.map { |img| img[:absolute_url] }
      end

      json = JSON.pretty_generate(article_data)

      content_tag(:script, json, { type: "application/ld+json" }, false)
    end
  end
end
