# typed: true
# frozen_string_literal: true

module Site
  module Header
    class GlobalNavLink
      attr_reader :id, :label, :href, :octicon, :repo

      def initialize(id:, label:, href:, octicon:, repo:)
        @id = id
        @label = label
        @href = href
        @octicon = octicon
        @repo = repo
      end

      def selected_by_id
        "repo_#{repo.id}_#{id}_selected".to_sym
      end
    end
  end
end
