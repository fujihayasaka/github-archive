# typed: true
# frozen_string_literal: true

# Public: For getting the preferred CONTRIBUTING, README, SUPPORT,
# CODE_OF_CONDUCT, etc., files TreeEntry objects consistently.
#
# Looks in the repository's `.github/` folder, root, and `docs/`
# folders, in that order.
module PreferredFile
  TYPES = [
    :citation,
    :code_of_conduct,
    :codeowners,
    :contributing,
    :dashboard,
    :commands,
    :funding,
    :issue_template,
    :pull_request_template,
    :readme,
    :repository_hubot_task_list,
    :repository_task_list,
    :support,
    :license,
    :security,
    :token_scanning_configuration,
    :no_preferred_files_found_in_repo,
  ].freeze

  # Types that can be used as the global preferred health file
  # stored in a `.github` repository.
  GLOBAL_TYPES = [
    :code_of_conduct,
    :contributing,
    :funding,
    :issue_template,
    :pull_request_template,
    :security,
    :support,
  ].freeze

  # Types that can be subdirectories with user-specified files
  # within them.
  SUBDIRECTORY_TYPES = [
    :issue_template,
    :pull_request_template,
  ].freeze

  # Types that can have multiple files of the same type.
  MULTIPLE_TYPES = [
    :license
  ].freeze

  # Types relevant for prompting users prior to contribution, etc.
  COMMUNITY_GUIDELINE_TYPES = [
    :code_of_conduct,
    :contributing,
    :support,
  ].freeze

  # Paths of subdirectories to search for preferred files, in the
  # order they'll be searched.
  SUBDIRECTORIES_IN_SEARCH_ORDER = [
    ".github",
    ".",
    "docs",
  ].freeze

  ROOT_TYPES = [
    :citation,
    :license
  ].freeze

  # Matches one of SUBDIRECTORIES_IN_SEARCH_ORDER
  SUBDIRECTORY_REGEXP = /\A#{Regexp.union(SUBDIRECTORIES_IN_SEARCH_ORDER)}\z/i

  R_CFF = /\ACITATION\.cff\z/i
  R_BIB = /\ACITATIONS?\.bib\z/i
  R_MD = /\ACITATIONS?\.md\z/i
  R_NO_EXT = /\ACITATIONS?\z/i
  R_INST = /\ACITATION\z/i
  # Valid citation files that can be shown in the `cite this repository` dropdown
  VALID_CITATION_REGEXP = Regexp.union(R_CFF, R_BIB, R_MD, R_NO_EXT)
  # Used in TreeEntry to hide warning banner on unparsable non-cff citations
  UNPARSABLE_CITATION_REGEXP = Regexp.union(R_BIB, R_MD, R_NO_EXT)

  # Public: Does a given path match valid paths for a given
  #         PreferredFile type?
  #
  # type - The Symbol type of PreferredFile.
  # path - A path String to compare against.
  #
  # Returns true if the a file of the given type would be
  # recognized at the given path.
  #
  # Returns a Boolean.
  # Raises an ArgumentError if type isn't in TYPES.
  def self.valid_path?(type:, path:)
    require_valid_type(type)
    return false unless path.present?

    SUBDIRECTORY_REGEXP =~ File.dirname(path) && type_regex_for(type) =~ File.basename(path)
  end

  # Public: For getting the preferred CONTRIBUTING, README, SUPPORT, LICENSE,
  # CODE_OF_CONDUCT, etc., files TreeEntry objects consistently.
  #
  # See PreferredFile::Types for the list of all types.
  #
  # Looks in the repository's `.github/` folder, root, and `docs/` folders,
  # in that order.
  #
  # Looks through the files in alphabetical order and, if a formatted file is
  # found, returns it, otherwise returning a plaintext version if present.
  #
  # Ignores any unrecognized file extensions.
  #
  # Follows symlinks.
  #
  # directory - The Directory to search within.
  # type - The Symbol type of preferred file to find.
  # nested_filename - Optionally, a String name for a file under a directory
  #                   with name `type`, where `type` is in SUBDIRECTORY_TYPES.
  #
  # NOTE: The nested_filename argument is likely user-supplied!!
  #
  # Returns a TreeEntry for the file if one is found, nil otherwise.
  # Raises an ArgumentError if type isn't in TYPES or is misused.
  def self.find(directory:, type:, nested_filename: nil, subdirectories: SUBDIRECTORIES_IN_SEARCH_ORDER)
    return nil unless directory

    require_valid_type(type)
    require_subdirectory_type(type) if nested_filename

    # Certain files must be at the repository root
    if ROOT_TYPES.include?(type)
      subdirectories = ["."]
      if type == :citation
        subdirectories.push("inst")
      end
    end

    subdirectories.each do |subdirectory_name|
      subdirectory_name = actual_subdirectory_name(directory, subdirectory_name)
      next unless subdirectory_name

      if nested_filename
        subdirectory = directory.repository.directory(
          directory.commit_sha,
          subdirectory_name,
        )
        subsubdirectory_name = actual_subdirectory_name(subdirectory, type, allow_plural: true)
        next unless subsubdirectory_name

        search_path = File.join(subdirectory_name, subsubdirectory_name)
        search_regex = case_insensitive_regex_for(nested_filename)
      else
        search_path = subdirectory_name
        search_regex = type_regex_for(type, subdirectory: subdirectory_name)
      end

      if file = search_blob_entries(directory, search_path, search_regex, type).first
        return file.resolve_symlink
      end
    end

    nil
  end

  # Similar to the `.find` method but returns all entries for the given type.
  # This is only useful for any file types that may have subdirectories to
  # search through, such as issue or pull request templates.
  #
  # For example, if there are multiple issue templates under
  # `.github/ISSUE_TEMPLATE`, it returns all of them instead of the first one we
  # find.
  #
  # All other types are ignored.
  #
  # directory - The Directory to search within.
  # type - The Symbol type of preferred file to find. Limited to types under
  #        SUBDIRECTORY_TYPES & MULTIPLE_TYPES only.
  def self.find_all(directory:, type:, subdirectories: SUBDIRECTORIES_IN_SEARCH_ORDER)
    return [] unless directory

    require_subdirectory_or_multi_type(type)

    matching_entries = []

    subdirectories.each do |subdirectory_name|
      # get the actual directory name in the correct case
      subdirectory_name = actual_subdirectory_name(directory, subdirectory_name)
      next unless subdirectory_name

      # find any entries with the type in its filename, e.g. ISSUE_TEMPLATE.md
      search_path = subdirectory_name
      search_regex = type_regex_for(type)
      matching_entries << search_blob_entries(directory, search_path, search_regex, type)

      # get the actual nested directory name in the correct case
      subdirectory = directory.repository.directory(
        directory.commit_sha,
        subdirectory_name,
      )
      nested_directory_name = actual_subdirectory_name(subdirectory, type, allow_plural: true)
      next unless nested_directory_name

      # find any entries in nested directories for the type such as
      # .github/ISSUE_TEMPLATE/foo.md
      search_path = File.join(subdirectory_name, nested_directory_name)
      search_regex = /\A.*\.md\z/i
      matching_entries << search_blob_entries(directory, search_path, search_regex, type)
    end

    matching_entries.flatten.compact.each(&:resolve_symlink)
  end

  # Public: Checks if a given tree entry is a type of preferred file.
  #
  # tree_entry    - The TreeEntry to test.
  # type          - The Symbol type of preferred file to check against.
  #
  # Returns a boolean.
  def self.is_type?(tree_entry:, type:)
    return false unless tree_entry.blob?

    looks_like_type = filename_is_type?(filename: tree_entry.name, type: type)
    looks_like_type && (tree_entry.formatted? || tree_entry.plaintext?)
  end

  # Public: Checks if a given filename is a type of preferred file.
  #
  # filename      - The filename to check.
  # type          - The Symbol type of preferred file to check against.
  #
  # Returns a boolean.
  def self.filename_is_type?(filename:, type:)
    require_valid_type(type)
    filename =~ type_regex_for(type)
  end

  class << self
    # Private: Validates that there is a subdirectory at path,
    # but allows for casing differences.
    #
    # directory - The Directory to search in.
    # subdirectory_name - The String name of a subdirectory to find.
    # allow_plural - (Optional) Boolean for matching the standard pluralization
    #                of the subdirectory name in addition to the exact one.
    #                Default: false.
    #
    # Returns the name of a subdirectory that matches the given name,
    # where the matching is case-insensitive and dashes match underscores
    # and vice-versa.
    #
    # If there is no subdirectory at path, will return nil.
    #
    # Returns a String or nil.
    private def actual_subdirectory_name(directory, subdirectory_name, allow_plural: false)
      # "." isn't actually a TreeEntry, so return the empty search
      # path below directory.
      return "" if subdirectory_name.eql?(".")

      name_regex = case_insensitive_regex_for(subdirectory_name, allow_plural: allow_plural)
      directory.tree_entries.detect do |entry|
        next unless entry.directory?
        name_regex =~ entry.name
      end&.name
    end

    # Private: Given a subdirectory path, search its entries, in order,
    # for matching blobs and return them.
    #
    # directory - The Directory being searched in.
    # search_path - A String subdirectory path within directory.
    # search_regex - A Regexp that is used to find a matching blob.
    # type - Symbol representing the type of preferred file to find
    #
    # Returns matching blobs as `TreeEntry`s or an empty array if none matches.
    private def search_blob_entries(directory, search_path, search_regex, type)
      _, directory_entries, _ = directory.repository.tree_entries(
        directory.commit_sha,
        File.join(directory.path.to_s, search_path.to_s),
      )

      directory_entries.select! do |entry|
        next unless entry.blob?
        # use utf-8 encoded file name to ensure it can be compared against regex
        next unless entry.display_name =~ search_regex
        entry.formatted? || entry.plaintext?
      end
      directory_entries.sort_by! do |entry|
        if type == :license
          1 - Licensee::ProjectFiles::LicenseFile.name_score(entry.name)
        elsif type == :citation && entry.name.end_with?(".cff")
          [0, entry.name.downcase]
        else
          [entry.formatted? ? 0 : 1, entry.name.downcase]
        end
      end
      directory_entries
    end

    # Private: Raise error unless type is within TYPES.
    #
    # type - The Symbol type.
    #
    # Returns true if valid.
    # Raises ArgumentError otherwise.
    private def require_valid_type(type)
      return true if TYPES.include?(type)
      raise ArgumentError.new("#{type.inspect} must be one of #{TYPES.inspect}")
    end

    # Private: Raise error unless type is within SUBDIRECTORY_TYPES.
    #
    # type - The Symbol type.
    #
    # Returns true if valid.
    # Raises ArgumentError otherwise.
    private def require_subdirectory_type(type)
      return true if SUBDIRECTORY_TYPES.include?(type)
      raise ArgumentError.new("#{type.inspect} can't be searched as a subdirectory (must be one of #{SUBDIRECTORY_TYPES.inspect})")
    end

    # Private: Raise error unless type is within SUBDIRECTORY_TYPES or MULTIPLE_TYPES.
    #
    # type - The Symbol type.
    #
    # Returns true if valid.
    # Raises ArgumentError otherwise.
    private def require_subdirectory_or_multi_type(type)
      return true if SUBDIRECTORY_TYPES.include?(type) || MULTIPLE_TYPES.include?(type)
      raise ArgumentError.new(
        "#{type.inspect} can't be searched as a subdirectory (must be one of #{SUBDIRECTORY_TYPES.inspect}) or does not support multiple files (must be one of #{MULTIPLE_TYPES.inspect})")
    end

    # Private: A mapping of Regexp matchers for known PreferredFile
    # formats.
    #
    # type_or_typedir - A Symbol or String corresponding to a preferred file
    #                   type or a "type subdirectory" name.
    #
    # By default, returns a Regexp that matches case-insensitive,
    # extension agnostic, and with '-' and '_' as equivalent.
    #
    # Special cases:
    #   - CODEOWNERS doesn't allow a file extension.
    #   - Task lists have specific file name to match.
    #   - Codes of Conduct can have a family prefix of language suffix
    #
    # Returna a Regexp or nil.
    private def type_regex_for(type_or_typedir, subdirectory: nil)
      case type_or_typedir
      when :citation
        subdirectory == "inst" ? R_INST : VALID_CITATION_REGEXP
      when :codeowners
        /\Acodeowners\z/i
      when :repository_hubot_task_list
        /\Ahubot\.yml\z/i
      when :repository_task_list
        /\Atasks\.yml\z/i
      when :code_of_conduct
        /\A#{Coconductor::ProjectFiles::CodeOfConductFile::FILENAME_REGEX}\z/i
      when :dashboard
        /\A__dashboard\.md\z/i
      when :commands
        /\A__commands\.json\z/i
      when :funding
        /\Afunding\.ya?ml\z/i
      when :license
        regexes = Licensee::ProjectFiles::LicenseFile::FILENAME_REGEXES
        Regexp.union(regexes.reject { |_r, score| score == 0.00 }.keys)
      when :token_scanning_configuration
        /\Asecret_scanning\.yml\z/i
      when :security
        /\Asecurity(\.md)?\z/i
      when *TYPES
        /\A#{type_or_typedir.to_s.gsub("_", "[_-]")}(\.[^.]+)?\z/i
      end
    end

    # Private: Return a Regexp that matches exactly, save for case.
    #
    # dir_or_file - A String directory or file name.
    # allow_plural - (Optional) Boolean for matching the standard pluralization
    #                of the directory or file name in addition to the exact one.
    #                Default: false.
    #
    # Returns a Regexp.
    private def case_insensitive_regex_for(dir_or_file, allow_plural: false)
      return /\A#{Regexp.escape(dir_or_file)}\z/i unless allow_plural
      /\A(?:#{Regexp.escape(dir_or_file)}|#{Regexp.escape(dir_or_file.to_s.pluralize)})\z/i
    end
  end
end
