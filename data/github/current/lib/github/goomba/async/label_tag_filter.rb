# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class LabelTagFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers

    MAX_SNIPPET_LINE_INDEX = 11
    SELECTOR = Goomba::Selector.new(match: "gh|label-mention")
    TIMEOUT = 1 # second

    def self.cache_key(context)
      return unless context[:for_email]
      "label_tag_for_email"
    end

    def initialize(*)
      super
      @label_cache = {}
    end

    def selector
      SELECTOR
    end

    def async_scan
      Promise.all(@nodes.map do |node|
        decoded_label = CGI::unescape(node["label"])
        Platform::Loaders::LabelByName.load(repository, decoded_label).then do |label|
          @label_cache[node["label"]] = label
        end
      end)
    end

    # Translates a `<gh:label-mention>` tag into regular HTML.
    def call(node)
      label = @label_cache[node["label"]]

      link = ActionController::Base.helpers.link_to node["text"], node["permalink"]
      return link if !label

      rich_label = if context[:for_email]
        ApplicationController.render(partial: "mailers/issues/label", locals: { label: label, href: node["permalink"]  }, formats: [:html], layout: false)
      else
        ApplicationController.render(partial: "issues/markdown_label", locals: { label: label, href: node["permalink"]  }, formats: [:html], layout: false)
      end

      repository_resource_reference_wrapper(label) do |wrapper|
        wrapper.authorized { rich_label }
        wrapper.unauthorized { link }
      end
    end
  end
end
