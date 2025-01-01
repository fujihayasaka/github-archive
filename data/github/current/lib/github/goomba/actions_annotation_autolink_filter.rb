# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # HTML Filter for auto_linking urls that belong to valid domains and subdomains
  # for linkified annotations.
  #
  # Context options:
  #   :autolink  - boolean whether to autolink urls
  #   :link_attr - HTML attributes for the link that will be generated
  #   :skip_tags - HTML tags inside which autolinking will be skipped.
  #                See Rinku.skip_tags
  #   :flags     - additional Rinku flags. See https://github.com/vmg/rinku
  #
  # This filter does not write additional information to the result hash.
  class ActionsAnnotationAutolinkFilter < InputFilter
    def self.enabled?(context)
      context[:autolink] != false
    end

    def self.cache_key(context)
      [
        ("skip_tags" if context[:skip_tags]),
        ("actions_annotation_autolink_flags=#{context[:flags]&.join(",")}" if context[:flags]),
      ].reject(&:blank?).join(":")
    end

    def call(html)
      ::HTML::Pipeline::ActionsAnnotationAutolinkFilter.new(html, context, result).call
    end
  end
end
