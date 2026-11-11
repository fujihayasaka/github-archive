# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Models
    class InboxSections
      # Maximum byte length of a raw cookie value we'll attempt to parse.
      # Prevents abuse via oversize cookie payloads.
      MAX_COOKIE_BYTES = 1024

      class Section < T::Struct
        const :id, String
      end

      sig { returns(T::Array[Section]) }
      def self.sections
        sections = [
          Section.new(id: "review-requested"),
          Section.new(id: "team-review-requested"),
          Section.new(id: "your-drafts"),
          Section.new(id: "waiting-for-review"),
          Section.new(id: "needs-action"),
          Section.new(id: "ready-to-merge"),
          Section.new(id: "merge-queue")
        ]
      end

      sig { returns(T::Array[String]) }
      def self.default_order
        sections.map(&:id)
      end

      sig { params(id: String).returns(T.nilable(Section)) }
      def self.find(id)
        sections.find { |section| section.id == id }
      end

      # Returns true when the given string is a registered section name.
      sig { params(query_or_section_id: String).returns(T::Boolean) }
      def self.named_query?(query_or_section_id)
        find(query_or_section_id) != nil
      end

      # Parses the comma-separated cookie value and returns the subset of
      # section IDs that are valid registered sections.
      sig { params(raw: T.nilable(String)).returns(T::Array[String]) }
      def self.collapsed_section_ids_from_cookie(raw)
        parse_section_ids(raw)
      end

      # Parses the comma-separated cookie value for the user's section order
      # preference.
      #
      # Returns `[]` when the cookie is missing or empty so the frontend can
      # apply its own canonical default order.
      # When the cookie is present, returns the user's chosen order followed
      # by any registered sections missing from it.
      #
      sig { params(raw: T.nilable(String)).returns(T::Array[String]) }
      def self.ordered_section_ids_from_cookie(raw)
        from_cookie = parse_section_ids(raw)
        return [] if from_cookie.empty?

        missing = default_order - from_cookie
        from_cookie + missing
      end

      # Parses the comma-separated cookie value for the user's hidden sections
      # preference. Returns the validated subset of section IDs the user has
      # chosen to hide.
      #
      sig { params(raw: T.nilable(String)).returns(T::Array[String]) }
      def self.hidden_section_ids_from_cookie(raw)
        parsed = parse_section_ids(raw)
        return [] unless valid_visibility?(parsed)
        parsed
      end

      # Returns true unless `hidden_ids` would hide every registered section.
      # Used to validate that the user always has at least one visible section.
      sig { params(hidden_ids: T::Array[String]).returns(T::Boolean) }
      def self.valid_visibility?(hidden_ids)
        available = sections.map(&:id)
        hidden_set = hidden_ids.uniq.to_set
        available.any? { |id| !hidden_set.include?(id) }
      end

      # Returns a map of section IDs — the client always sends named IDs,
      # and the server resolves them to actual ES queries via SearchConfig.
      sig { returns(T::Hash[String, String]) }
      def self.query_map
        sections.each_with_object({}) do |section, map|
          map[section.id] = section.id
        end
      end

      # Shared parser for comma-separated, validated section ID cookie values.
      # Caps both raw input length and resulting list length to prevent abuse.
      sig { params(raw: T.nilable(String)).returns(T::Array[String]) }
      private_class_method def self.parse_section_ids(raw)
        return [] unless raw.present?
        return [] if raw.bytesize > MAX_COOKIE_BYTES

        raw.split(",").map(&:strip).uniq.select { |id| named_query?(id) }.first(sections.length)
      end
    end
  end
end
