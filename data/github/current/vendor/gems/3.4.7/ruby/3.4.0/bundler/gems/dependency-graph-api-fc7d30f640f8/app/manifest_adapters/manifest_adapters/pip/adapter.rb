require "tomlrb"

module ManifestAdapters
  module Pip
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case File.join("/", path.to_s, filename.to_s)
        when /(\A|\/)pipfile\Z/i                                        then Types::Manifest[:pipfile]
        when /(\A|\/)pipfile\.lock\Z/i                                  then Types::Manifest[:pipfile_lock]
        when /(\A|\/)setup\.py\Z/i                                      then Types::Manifest[:setup_py]
        when /(\A|\/)pyproject\.toml\Z/i                                then Types::Manifest[:pyproject_toml]
        when /(\A|\/)poetry\.lock\Z/i                                   then Types::Manifest[:poetry_lock]

        # Regex rule for detecting `requirements` string in python requirements.txt manifest name due to irregular naming:
        # Allow only a hyphen, period or underscore before requirements OR check that requirements is the beginning of the string.
        # Don't allow whitespace after requirements
        # Allow for other things after requirements, like requirements.prod.txt
        when /(?:\-|\.|\_|\A|\/)requirements[^\s]*\.txt\Z/i             then Types::Manifest[:requirements_txt]

        # More lenient Regex rule for detecting `require` string in python requirements.txt manifest name due to irregular naming:
        # Allow anything except multiple periods OR whitespace before/after require.
        # Allow hyphen or underscore after require followed by non-period and non-whitespace characters.
        # Don't allow require to be a substring, e.g. don't allow "required.txt".
        # Requirements.tx can have a hyphen, underscore or forward slash before and after it.
        when /(?:[^\s|\.]*)require(?:(?:\-|\_|\/)[^\s|\.]*)?\.txt\Z/i   then Types::Manifest[:requirements_txt]
        end
      end

      def self.package_manager
        Types::PackageManager[:pip]
      end

      private

      def parsed
        @parsed ||= case manifest_type
        when Types::Manifest[:requirements_txt]
          Pip::Parsers::RequirementsTxt.new(content, filename: filename, path: path)
        when Types::Manifest[:pipfile]
          Pip::Parsers::Pipfile.new(content)
        when Types::Manifest[:pipfile_lock]
          Pip::Parsers::PipfileLock.new(content)
        when Types::Manifest[:setup_py]
          Pip::Parsers::SetupPy.new(content)
        when Types::Manifest[:pyproject_toml]
          Pip::Parsers::PyprojectToml.new(content)
        when Types::Manifest[:poetry_lock]
          Pip::Parsers::PoetryLock.new(content)
        end
      end
    end
  end
end
