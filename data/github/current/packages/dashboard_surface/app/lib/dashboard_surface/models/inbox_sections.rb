# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Models
    class InboxSections
      class Section < T::Struct
        const :id, String
      end

      sig { returns(T::Array[Section]) }
      def self.sections
        sections = [
          Section.new(id: "ready-to-merge"),
          Section.new(id: "needs-action"),
          Section.new(id: "review-requested"),
          Section.new(id: "team-review-requested"),
          Section.new(id: "merge-queue")
        ]
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

      # Returns a map of section IDs — the client always sends named IDs,
      # and the server resolves them to actual ES queries via SearchConfig.
      sig { returns(T::Hash[String, String]) }
      def self.query_map
        sections.each_with_object({}) do |section, map|
          map[section.id] = section.id
        end
      end
    end
  end
end
