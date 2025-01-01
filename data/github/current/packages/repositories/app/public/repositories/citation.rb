# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cff"

module Repositories
  class Citation
    include UrlHelper

    def self.exists?(repository, tree_name: nil)
      return false unless repository
      get_local_file(repository, tree_name: tree_name).present?
    end

    def self.from_repository(repository, tree_name: nil)
      local_file = get_local_file(repository, tree_name: tree_name)
      return nil if local_file.nil?
      new(local_file, tree_name: tree_name)
    end

    def initialize(tree_entry, tree_name: nil)
      @repository = tree_entry.repository
      @tree_name = tree_name
      load_data(tree_entry)
    end

    def message
      @data.message
    end

    # Leaning on https://f1000research.com/articles/9-1257/v2 for reference.
    def format(format_type)
      return unless self.valid?
      case format_type
      when :apa
        @data.to_apalike
      when :bibtex
        @data.to_bibtex
      else
        raise ArgumentError, "invalid format #{format_type}"
      end
    end

    def file_path
      return @file_path if defined?(@file_path)
      @file_path = preferred_file_path(type: :citation, repository: @repository, tree_name: @tree_name)
    end

    def valid?
      @data != nil && !(@data.to_apalike.nil? && @data.to_bibtex.nil?) && !@failed_to_load_data
    rescue NoMethodError => err
      @failed_to_load_data = true
      GitHub.dogstats.increment("citation.valid.error", tags: ["error:#{err.class.name}"])

      false
    end

    def self.get_local_file(repository, tree_name: nil)
      branch = tree_name || repository.default_branch
      PreferredFile.find(directory: repository.directory(branch), type: :citation)
    end
    private_class_method :get_local_file

    def self.help_url
      "https://docs.github.com/github/creating-cloning-and-archiving-repositories/creating-a-repository-on-github/about-citation-files"
    end

    private

    def load_data(tree_entry)
      @data = ::CFF::Index.read(tree_entry.data)
      fixup_version
    rescue Psych::Exception, NoMethodError => err
      @failed_to_load_data = true
      GitHub.dogstats.increment("citation.parse.error", tags: ["error:#{err.class.name}"])
    end

    # Private: The version of software that is being used as defined
    # in the CITATION file. If a version is not defined we can use
    # the latest sha as mentioned in
    # https://f1000research.com/articles/9-1257/v2#FN2.
    #
    # Returns a String.
    def fixup_version
      unless @data.version
        if (ref = @repository.heads.find(@repository.default_branch))
          @data.version = ref.commit.oid
        end
      end
    end
  end
end
