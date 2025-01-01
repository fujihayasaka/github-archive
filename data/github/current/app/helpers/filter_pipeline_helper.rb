# typed: true
# frozen_string_literal: true

module FilterPipelineHelper
  # Convert all Strings to UTF-8 so the entire YAML table will be UTF-8.
  # Also, makes emoji work.
  def transcode_yaml_value(value)
    if value.is_a?(String) && value.encoding != Encoding::UTF_8
      GitHub::Encoding.try_guess_and_transcode(value.frozen? ? value.dup : value)
    else
      value
    end
  end
end
