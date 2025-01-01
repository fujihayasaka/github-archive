# typed: true
# frozen_string_literal: true

module Site
  class FaqComponent < ApplicationComponent
    VERSION = "1.0.0"
    DEPENDENCIES = {
      Site::FaqGroupComponent.name => Site::FaqGroupComponent::VERSION,
      Site::FaqItemComponent.name => Site::FaqItemComponent::VERSION
    }

    def initialize(classes: nil, headline_size: :medium, headline_classes: nil, items: [], groups: [])
      @classes = classes
      @headline_size = headline_size
      @headline_classes = headline_classes
      @items = items
      @groups = groups
      @digest = Digest::SHA256.hexdigest("#{@items.present? ? @items.to_json : "items"}_#{@groups.present? ? @groups.to_json : "groups"}#{DEPENDENCIES.to_json}")
    end

    def cache_key
      "site_faq_#{VERSION}_#{@digest}"
    end

    def structured_data_cache_key
      "site_faq_structured_data_#{@digest}"
    end

    def structured_data_script_tag(items: @items, groups: @groups)
      @flattened_groups = @groups.flat_map { |group| group[:items] }
      @flattened_items = @items + @flattened_groups

      if !@flattened_items.empty?
        @structured_data = {
          "@context": "https://schema.org",
          "@type": "FAQPage",
          "mainEntity": @flattened_items.map do |item|
            {
              "@type": "Question",
              "name": item[:question],
              "acceptedAnswer": {
                "@type": "Answer",
                "text": GitHub::Goomba::MarkdownPipeline.to_html(item[:answer], cache_settings: { use_cache: true })
              }
            }
          end
        }

        content_tag(:script, json_escape(@structured_data.to_json).html_safe, type: "application/ld+json") # rubocop:disable Rails/OutputSafety
      end
    end

    def section_headline_classes
      class_names(
        "color-fg-default mb-md-8",
        @headline_classes,
        {
          "mx-auto text-center col-5-max mb-5": !@groups.present?,
          "h2-mktg": @headline_size == :large,
          "h3-mktg": @headline_size == :medium,
          "h4-mktg": @headline_size == :small,
        }
      )
    end
  end
end
