# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Replaces placeholder links from CodeQL alert messages for code quality with real links
  # that point to file locations on GitHub
  #
  # Context options:
  #   :related_locations (required) - array of related_locations for this result
  #   :entity (required)            - repository in which this result occurs
  #   :commit_oid (required)        - commit in which this result occurs
  class CodeQualityMessageLinkFilter < NodeFilter
    include ActionView::Helpers::TagHelper

    SELECTOR = Goomba::Selector.new("a[href]")

    def selector
      SELECTOR
    end

    def self.cache_key(context)
      [
        context[:commit_oid],
        context[:related_locations]
      ].reject(&:blank?).join(":")
    end

    def self.enabled?(context)
      context[:related_locations].present? &&
        context[:entity].is_a?(Repository) &&
        context[:commit_oid].present?
    end

    def call(element)
      return unless should_process?

      # try to parse the href as an integer
      link_index = href_index(element)
      return unless link_index.present?

      related_location = related_location_from_link_index(link_index)
      return unless related_location.present?

      repository = context[:entity]

      href = blob_path(
        repository:,
        commit_oid: context[:commit_oid],
        file_path: related_location.location.file_path,
        start_line: related_location.location.start_line,
        end_line: related_location.location.end_line,
      )

      content_tag(:a, element.text_content, class: "Link", href: href)
    end

    private

    def should_process?
      context[:related_locations].present? &&
        context[:entity].is_a?(Repository) &&
        context[:commit_oid].present?
    end

    def href_index(element)
      begin
        Integer(element.attributes["href"], 10)
      rescue ArgumentError
        # nothing to do if the href is not an integer
        nil
      end
    end

    def related_location_from_link_index(link_index)
      context[:related_locations].find do |loc|
        loc.replacement_index == link_index
      end
    end

    def blob_path(repository:, commit_oid:, file_path:, start_line:, end_line:)
      "/#{repository.name_with_display_owner}/blob/#{commit_oid}/#{UrlHelper.escape_branch(file_path)}#L#{start_line}-L#{end_line}"
    end
  end
end
