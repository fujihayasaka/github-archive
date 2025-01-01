# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Filter that represents YAML front matter as HTML
  class YamlFilter < InputFilter
    FRONTMATTER_REGEX = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

    attr_reader :blob

    def call(input)
      @blob = context[:blob]
      return unless can_render_blob?

      render_yaml_frontmatter(blob.data.to_s)
    end

    def render_yaml_frontmatter(content)
      match = content.match(FRONTMATTER_REGEX)
      return unless match

      begin
        # definition of a YAML header
        data = YAML.safe_load(match[1], permitted_classes: [Date, Symbol, Time])
      rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError => boom
        # If there is an error in the YAML, show the user that error so they can fix it
        # Alias parsing is intentionally disabled, show a more helpful message to users
        message = boom.is_a?(Psych::AliasesNotEnabled) ? "Alias parsing is not enabled." : boom.message
        result[:user_error] = "Error in user YAML: #{message}"

        frontmatter = render_error(match[0]) + GitHub::HTMLSafeString::NEW_LINE
      # We want to avoid raising a 500 because of user generated content, so if Psych raises due to some oddity
      # in the frontmater, we should catch it instead but keep the error generic so we don't end up leaking
      # any implementation details.
      rescue => e # rubocop:disable Lint/RescueException
        # log instead of needle so that we don't get bombarded with errors due to ill-formatted user content
        GitHub.logger.info("Failed to render YAML frontmatter", {
          "code.namespace": self.class.name,
          "code.function": __method__,
          error_message: e.message,
          backtrace: e.backtrace
        })

        result[:user_error] = "Error in parsing user YAML"

        frontmatter = render_error(match[0]) + GitHub::HTMLSafeString::NEW_LINE
      else
        # avoids content that's not YAML
        return unless data.is_a?(Hash)
        # process_yaml already includes a trailing space
        frontmatter = process_yaml(data, outermost_table: true)
      end

      result[:frontmatter_skip] = match[0].size
      result[:frontmatter] = frontmatter + GitHub::HTMLSafeString::NEW_LINE

      nil
    end

    def process_yaml(data, outermost_table: false)
      th_row = []
      tb_row = []
      tr_row = nil

      # checks for whether the YAML is an array, including an array of Hashes
      is_array = data.is_a?(Array)
      is_hash_array = data.any? { |d| d.is_a?(Hash) }

      if is_hash_array && !is_array
        data[0].each_key do |header|
          th_row << header
        end
      # we can skip simple arrays, because they'll be represented as <table>s
      elsif !is_array
        data.each_key do |header|
          th_row << header
        end
      end

      elements = is_array ? data : data.values

      elements.each do |value|
        if value.is_a?(Array) || value.is_a?(Hash)
          tb_row << process_yaml(value)
        else
          tb_row << value
        end
      end

      ApplicationController.render(partial: "filter_partials/yaml_table",
        formats: [:html],
        locals: {
          th_row: th_row,
          tb_row: tb_row,
          outermost_table: outermost_table,
        }
      )
    end

    # Internal: Determine if we should try to render the blob via the
    # GitHub::Markup gem. We won't render the blob if it is binary or if it is
    # too big.
    #
    # Returns true if we can safely render the blob.
    def can_render_blob?
      !context[:plaintext] && GitHub::HTML::MarkupFilter.can_render_blob?(blob)
    end

    private def render_error(text)
      ActionController::Base.helpers.content_tag(:pre, lang: :yaml) do
        ActionController::Base.helpers.content_tag(:code) do
          GitHub::HTMLSafeString::NEW_LINE + text
        end
      end
    end
  end
end
