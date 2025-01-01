# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Replaces placeholder links from turbo scan alert messages with real links
  # that point to file locations on GitHub
  #
  # Context options:
  #   :related_locations (required) - array of related_locations for this result
  #   :entity (required)            - repository in which this result occurs
  #   :commit_oid (required)        - commit in which this result occurs
  class CodeScanningMessageLinkFilter < NodeFilter
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

      ApplicationController.render(
        partial: "repos/code_scanning/related_location_popover",
        locals: {
          link_text: element.text_content,
          related_location: related_location,
          commit_oid: context[:commit_oid],
          view: RepositoryCodeScanning::View.new(repository: repository),
        },
        formats: [:html],
      ).gsub("\n", "")
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
  end
end
