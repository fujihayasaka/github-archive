# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # HTML Filter for auto_linking urls in HTML.
  #
  # Context options:
  #   :autolink  - boolean whether to autolink urls
  #   :link_attr - HTML attributes for the link that will be generated
  #   :skip_tags - HTML tags inside which autolinking will be skipped.
  #                See Rinku.skip_tags
  #   :flags     - additional Rinku flags. See https://github.com/vmg/rinku
  #
  # This filter does not write additional information to the result hash.
  class AutolinkFilter < InputFilter
    def self.enabled?(context)
      context[:autolink] != false
    end

    def self.cache_key(context)
      [
        ("skip_tags" if context[:skip_tags]),
        context[:link_attr]&.join(","),
        (context[:flags] if context.fetch(:flags, false)),
      ].reject(&:blank?).join(":")
    end

    def call(html)
      ::HTML::Pipeline::AutolinkFilter.new(html, context, result).call
    end
  end
end
