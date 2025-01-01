# typed: true
# frozen_string_literal: true

module Gists
  class EditorView < ::Blob::EditorView
    include GistsHelper

    attr_reader :gist, :oid

    delegate :owner, :has_truncated_files?, to: :gist

    def forked_repo?
      false
    end

    # Used to restrict the Preview tab to markdown files only when editing Gists
    def gist?
      true
    end

    def show_simple_diff?
      false
    end

    def markdown_file?
      filename&.ends_with?(*TreeEntry::MD_EXTENSIONS)
    end

    # Public: Does this edit mean the quick-pull workflow?
    #
    # Returns Boolean
    def quick_pull?
      false
    end

    # Public: Should a quick-pull choice even be offered?
    #
    # Returns Boolean
    def quick_pull_choice?
      false
    end

    # Is the Gist owned by the user?
    #
    # Returns Boolean
    def owned?
      gist.user == current_user
    end

    # Public: The textarea name that stores the blob contents
    def textarea_name
      "gist[contents][][value]"
    end

    # Public: How many rows should the editor textarea have?
    #
    # NOTE: We're maintaining the approx textarea row size from Gist-web
    #       to keep multi file editing easy.
    def textarea_rows
      17
    end

    def asset_types
      [:assets]
    end
  end
end
