# typed: true
# frozen_string_literal: true

module RepositoryCodeScanning
  class CodePathsView < ResultView
    def code_paths
      @code_paths ||= begin
        code_path = response&.data&.code_paths || []
        code_path.select { |code_path| code_path.steps.present? }
      end
    end

    def step_kind_for_index(code_path, index)
      if index == 0
        "source"
      elsif index == code_path.steps.size - 1
        "sink"
      else
        "intermediate"
      end
    end

    def paths_count_label
      @paths_count_label ||= [
        helpers.number_with_delimiter(code_paths.size),
        "path".pluralize(code_paths.size),
        "available"
      ].join(" ")
    end

    def code_path_labels
      @code_path_labels ||= code_paths.map do |code_path|
        [
          helpers.number_with_delimiter(code_path.steps.size),
          "step".pluralize(code_path.steps.size),
          "in",
          File.basename(code_path.steps.first.location.file_path)
        ].join(" ")
      end
    end

    def default_button_text
      @default_button_text ||= code_path_labels.first || paths_count_label
    end
  end
end
