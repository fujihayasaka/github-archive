# typed: true
# frozen_string_literal: true

module ScanningHelper
  def split_file_path_and_name(filepath)
    filepath = filepath&.delete("\u0000") # Remove null bytes
    return ["", ""] if filepath.blank?

    path = File.dirname(filepath)
    path = "" if path == "."
    path += "/" if !path.blank?
    [path, File.basename(filepath)]
  end

  # Takes a directory such as `root/first_dir/middle_dir/last_dir/file.ext` and truncates to `root/.../last_dir/file.ext`
  # Additionally, truncates each path segment to max_segment_length plus `...`
  def reverse_truncate_path(path, max_segment_length)
    directory_levels = path.split("/")

    directory_levels.map! do |level|
      next level[0, max_segment_length] + "..." if level.length > max_segment_length
      level
    end

    return directory_levels[0] + "/.../" + directory_levels[-2] + "/" + directory_levels[-1] if directory_levels.length > 3
    directory_levels.join("/")
  end
end
