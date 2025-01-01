# typed: true
# frozen_string_literal: true

module Site
  module ReadmeHelper
    include StaticAssetHelper, ActionView::Helpers::TagHelper, ERB::Util

    def category_meta_image_path(category_slug)
      if category_slug == "podcast"
        return image_path("modules/site/social-cards/readme-project-podcast.jpg")
      end

      image_path("modules/site/social-cards/readme-project.jpg")
    end

    def fullname(person)
      return nil if person.blank?

      format_person_name = ->(first_name, last_name) { "#{first_name} #{last_name}".strip }

      return format_person_name.call(person[:first_name], person[:last_name]) if person.is_a?(Hash)

      format_person_name.call(person.first_name, person.last_name)
    end

    def preview_label
      content_tag(:span, "PREVIEW", class: "color-fg-danger text-bold")
    end

    def article_structured_data_tag(headline:, publication_date:, authors: [], images: [])
      article_data = {
        "@context" => "http://schema.org",
        "@type" => "Article",
        "headline" => json_escape(headline),
        "datePublished" => publication_date,
        "publisher" => {
          "@type" => "Organization",
          "name" => "GitHub",
          "logo" => image_url("modules/open_graph/github-logo.png")
        }
      }

      if authors.present?
        article_data["author"] = authors.map do |author|
          next if author.blank?

          author_data = {
            "@type" => "Person",
            "name" => json_escape(fullname(author))
          }

          if author[:handle].present?
            author_data["url"] = user_url(author[:handle].strip)
          end

          author_data
        end
      end

      if images.present?
        article_data["image"] = images.map { |img| img[:absolute_url] }
      end

      json = JSON.pretty_generate(article_data)

      content_tag(:script, json, { type: "application/ld+json" }, false)
    end

    def readme_story_body_fragment_cache_key(story_json)
      content_type, slug, updated_at = story_json.values_at(:content_type, :slug, :updated_at)

      key = [content_type[:id], slug, "content_body", updated_at, "for_readme_staff:#{readme_staff?}"].join(".")

      "#{key}/v1"
    end

    private def user_url(handle)
      super(handle)
    rescue NoMethodError => e
      Failbot.report(e)
      false
    end

    private def readme_staff?
      super
    rescue NoMethodError => e
      Failbot.report(e)
      false
    end
  end
end
