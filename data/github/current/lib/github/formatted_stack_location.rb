# typed: true
# frozen_string_literal: true

module GitHub
  class FormattedStackLocation
    ROOT_SLASH = "#{Rails.root}/"
    GEM_SLASH = "#{Gem.dir}/"

    def self.from_location(location)
      new(location.absolute_path || location.path, location.lineno, location.label)
    end

    attr_reader :path, :line, :label

    def initialize(path, line, label = nil)
      @path = path
      @line = line
      @label = label
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def in_gem?
      @in_gem ||= @path.start_with?(GEM_SLASH)
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def in_root?
      @in_root ||= @path.start_with?(ROOT_SLASH)
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def in_app?
      !in_gem? && in_root?
    end

    def short_path
      @short_path ||=
        if in_gem?
          @path.slice((GEM_SLASH.length)..-1)
        elsif in_root?
          @path.slice((ROOT_SLASH.length)..-1)
        else
          @path
        end
    end

    def description
      @description ||=
        if @label
          "#{short_path}:#{@line} in #{@label}"
        else
          "#{short_path}:#{@line}"
        end
    end

    def linkable?
      !GitHub.enterprise? && in_app?
    end

    def view_source_url
      return unless linkable?

      "https://github.com/github/github/blob/#{GitHub.current_sha}/#{short_path}#L#{@line}"
    end
  end
end
