# typed: true
# frozen_string_literal: true

module PackageRegistry
  class PackageFile
    attr_reader :package_version_id, :filename, :guid, :size

    def initialize(p_file)
      @package_version_id = p_file.package_version_id
      @filename = p_file.filename
      @guid = p_file.guid
      @size = p_file.size
    end
  end
end
