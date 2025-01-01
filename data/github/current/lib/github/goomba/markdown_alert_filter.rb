# typed: true
# frozen_string_literal: true

#
# Must go before `TaskListFilter`, `Math*Filter`, `AnimatedImageFilter`, `TaskListFilter`, `RelativeLinkFilter` in
# the filter order. Neither of those filters work if the content that would trigger them is within a `blockquote` node
# that is being manipulated by another filter (in this case `MarkdownAlertFilter`) that comes **after** them in the
# order.
#
# Creates an Alert from a blockquote that starts with `[!NOTE]`, `[!IMPORTANT]`, `[!WARNING]`, `[!TIP]` or
# `[!CAUTION]`, for example:
#
# > [!NOTE]
# > This is a note!

module GitHub::Goomba
  class MarkdownAlertFilter < NodeFilter
    def self.rejection_list
      forbidden_parents = %w[blockquote details li p div]
      forbidden_parents.map { |tag| "#{tag} blockquote" }.join(", ")
    end

    SELECTOR = Goomba::Selector.new(match: "blockquote", reject: rejection_list)

    def selector
      SELECTOR
    end

    class Alert
      include OcticonsHelper

      ALERTS = {
        "NOTE" => {
          icon: "info"
        },
        "IMPORTANT" => {
          icon: "report"
        },
        "WARNING" => {
          icon: "alert"
        },
        "TIP" => {
          icon: "light-bulb"
        },
        "CAUTION" => {
          icon: "stop"
        }
      }

      attr_reader :type, :updated_paragraph

      def self.for_blockquote(node)
        node_html = node.to_html

        blockquote_children = node.children.select { |child| child.is_a?(Goomba::ElementNode) }
        first_element = blockquote_children.first
        return unless first_element.try(:tag) == :p

        first_element_content = first_element.inner_html
        match_data = first_element_content.match(/\A\[\!(.*?)\](?:(\n|<br>))?(.*)/m)
        return unless match_data

        type = match_data[1]
        line_break = match_data[2]
        content_after_line_break = match_data[3]

        return unless ALERTS.keys.any? { |alert| alert.casecmp?(type) }

        if no_line_break_with_content(line_break, content_after_line_break)
          return
        end

        if line_break_with_no_content(line_break, content_after_line_break)
          return unless blockquote_children.length > 1
        end

        if no_line_break_with_no_or_empty_content(line_break, content_after_line_break)
          return unless blockquote_children.length > 1
        end

        # We are striping the alert type from the content. Since this content has already been sanitized earlier in
        # the pipeline, it's safe to call html_safe.
        first_element_new_content = content_after_line_break&.strip&.html_safe # rubocop:disable Rails/OutputSafety

        first_element = if first_element_new_content.nil? || first_element_new_content.empty?
          nil
        else
          ActionController::Base.helpers.content_tag(
            first_element.tag,
            first_element_new_content,
            first_element.attributes
          )
        end

        new(type, first_element)
      end

      def initialize(type, updated_paragraph)
        @type = type
        @updated_paragraph = updated_paragraph
      end

      def new_title_paragraph
        title_html = ActionController::Base.helpers.content_tag(
          :p,
          EscapeHelper.safe_join([icon, @type.capitalize]),
          class: "markdown-alert-title"
        )
      end

      def self.no_line_break_with_content(line_break, content_after_line_break)
        line_break.nil? && content_after_line_break && !content_after_line_break.strip.empty?
      end
      private_class_method :no_line_break_with_content

      def self.line_break_with_no_content(line_break, content_after_line_break)
        line_break && content_after_line_break.strip.empty?
      end
      private_class_method :line_break_with_no_content

      def self.no_line_break_with_no_or_empty_content(line_break, content_after_line_break)
        line_break.nil? && (content_after_line_break.nil? || content_after_line_break.strip.empty?)
      end
      private_class_method :no_line_break_with_no_or_empty_content

      private

      def icon
        icon_name = ALERTS.dig(type.upcase, :icon)
        # We don't have the primer_octicon method in the OcticonHelper module,
        # this lint is intended to be run against app/, not lib/
        octicon(icon_name, class: "mr-2") # rubocop:disable Primer/PrimerOcticon
      end

    end

    def call(node)
      alert = Alert.for_blockquote(node)
      return unless alert

      type = alert.type.downcase
      adjusted_attributes = node.attributes.merge(class: "markdown-alert markdown-alert-#{type}")

      GitHub.dogstats.increment("markdown.highlight", tags: ["title:#{type}"])

      ActionController::Base.helpers.content_tag(
        :div,
        alert.new_title_paragraph + alert.updated_paragraph + remaining_content(node),
        adjusted_attributes
      )
    end

    private

    def remaining_content(node)
      other_content = node.children.drop_while { |child| !child.is_a?(Goomba::ElementNode) }.drop(1)
      # We have to drop the first node which we have manipulated above. Since this content has already been sanitized
      # earlier in the pipeline, it's safe to call html_safe.
      other_content.map(&:to_html).join.html_safe  # rubocop:disable Rails/OutputSafety
    end
  end
end
