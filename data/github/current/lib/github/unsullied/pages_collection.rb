# typed: true
# frozen_string_literal: true

module GitHub
  module Unsullied
    # An enumerable that represents all of the pages in a wiki repository.
    # A "page" is any renderable markup document in the repository, even if
    # nested in subdirectories.
    class PagesCollection

      include Enumerable

      DEFAULT_PAGE_NAME = "home"
      PREVIEW_NAME      = "_Preview"

      # Public: The list of rederable formats supported by wikis
      FORMAT_NAMES = {
        markdown: "Markdown",
        textile: "Textile",
        rdoc: "RDoc",
        org: "Org-mode",
        creole: "Creole",
        rest: "reStructuredText",
        asciidoc: "AsciiDoc",
        mediawiki: "MediaWiki",
        pod: "Pod",
      }

      # The Unsullied::Wiki object this collection is wrapping
      attr_reader :wiki

      def initialize(wiki)
        @wiki = wiki
      end

      # The GitRPC object used to perform all git operations on this wiki
      delegate :rpc, to: :wiki

      # Internal: The configured directory prefix for this wiki
      #
      # Returns a String
      def directory_prefix
        wiki.directory_prefix
      end

      # Public: Create a new wiki page
      #
      # name    - the name of the page as a String.
      # format  - the markup format used to render this page.
      # data    - the content of the page as a String
      # message - the message used in the commit created when committing the
      #           page to the repository
      # user    - a User object which is used as the committer
      #
      # Returns an Unsullied::Page object representing the newly created wiki
      # page.
      def create(name, format, data, message, user)
        if name.length > 2_000
          raise GitHub::Unsullied::Wiki::TitleTooLongError, "Page titles may not be longer than 2,000 characters"
        end

        check_for_duplicate(name)
        GitHub::Unsullied::Page.prevent_unwanted_edit!(wiki: wiki, user: user)

        if !user.has_primary_email?
          raise GitHub::Unsullied::Wiki::Error, "User has no primary email address"
        end

        parents = [wiki.default_oid]
        if message.blank?
          message = "Created #{name} (#{format})"
        end

        info = {
          "message"   => message,
          "committer" => {
            "name"  => user.git_author_name,
            "email" => user.git_author_email,
            "time"  => Time.zone.now.iso8601,
          },
        }

        data = GitHub::Unsullied::Page.normalize_newlines(data)
        name = GitHub::Unsullied::Page.treat_special_characters_for_saving(name)

        filename = GitHub::Unsullied::Page.make_filename(name, format)
        files = {
          filename => {
            "data" => data,
          },
        }

        oid = rpc.create_tree_changes(parents, info, files)
        wiki.update_default_ref(oid, user: user)

        if GitHub.flipper[:wiki_attachment_scanning].enabled?
          GitHub::Unsullied::Page.attach_matching_assets(wiki, files[filename]["data"], user)
        end

        find(name, oid)
      end

      # Public: Lookup a page by name (not case-sensitive) in the repository.
      # This will also search subdirectories as well. The first page found is
      # what will end up being returned.
      #
      # name - the page name as a String
      # oid  - the oid (as a 40 character String) of which to attempt to find
      #        the page.
      #
      # Returns an Unsullied::Page object representing the wiki page or nil
      def find(name, oid = wiki.default_oid)
        return if name.to_s.empty?

        match = T.let(nil, T.nilable(Unsullied::Page))
        each_entry(oid) do |page|
          if name_match?(name, page)
            match = page
            break
          end
        end
        match
      end

      # Public: Lookup the default (home) page for the wiki.
      #
      # Returns the default page for the wiki as an Unsullied::Page object, or
      # nil.
      def default(oid = wiki.default_oid)
        find(DEFAULT_PAGE_NAME, oid)
      end

      # Public: Fetch the most recently updated pages from the wiki.
      #
      # page  - the page number offset of which to start returning pages
      # limit - the number of pages to return
      # oid   - the revision oid (as a 40 character String) of which to start
      #         listing updated pages from
      #
      # Returns an array of Unsullied::Page objects
      def latest(page = 1, limit = 30, oid = wiki.default_oid)
        if page.nil? || page == 1
          offset = 0
        else
          offset = (page * limit).to_i - 1
        end

        entries = wiki.read_latest_wiki_pages(oid)
        entries[offset, limit].map do |path, commit_oid|
          entry = rpc.read_tree_entry(commit_oid, path)
          page = GitHub::Unsullied::Page.new(wiki, entry)
          page.revision_oid = commit_oid
          page
        end
      end

      # Public: Fetch the pages that were created, modified, or deleted between revisions.
      #
      # oid1 - the beginning revision (40 character String)
      # oid2 - the ending revision (40 character String)
      #
      # Returns an array of Unsullied::Page objects
      def changed_pages(oid1, oid2)
        modified_blobs = rpc.modified_blobs(oid1, oid2).values.flatten

        wiki_blobs = modified_blobs.select do |entry|
          filename = ::File.basename(entry["path"])
          GitRPC::Backend.valid_wiki_page?(filename)
        end

        pages = wiki_blobs.map do |wiki_blob|
          GitHub::Unsullied::Page.new(wiki, wiki_blob)
        end

        pages
      end

      # Public: Create a temporary Unsullied::Page object for use as a preview.
      #
      # format - the markup format used to render the page
      # data   - the content of the page to be previewed
      #
      # Returns an Unsullied::Page object
      def create_preview(format, data)
        filename = GitHub::Unsullied::Page.make_filename(PREVIEW_NAME, format)
        info = {
          "path" => filename,
          "data" => data,
          "type" => "blob",
          "mode" => 0100644,
          "size" => data.bytesize,
        }
        GitHub::Unsullied::Page.new(wiki, info)
      end

      # Public: Iterate over all of the pages in the wiki, excluding special
      # pages. Special pages start with a "_" character and currently include
      # "_Sidebar" and "_Footer".
      #
      # Each Unsullied::Page is yeilded to the block passed.
      #
      # oid - the revision oid (as a 40 character oid String) to start iterating
      #       over pages from.
      #
      # Returns nothing
      def each(oid = wiki.default_oid, &block)
        each_entry(oid) do |page|
          yield(page) unless special_page?(page.name)
        end
      end

      # Internal: Iterate over all of the pages in this wiki, including special
      # pages. Special pages start with a "_" character and currently include
      # "_Sidebar" and "_Footer".
      #
      # Each Unsullied::Page is yeilded to the block passed.
      #
      # oid - the revision oid (as a 40 character oid String) to start iterating
      #       over pages from.
      #
      # Returns nothing
      def each_entry(oid = wiki.default_oid)
        return if oid.nil?

        unique_pages = {}

        page_entries = rpc.read_wiki_pages(oid, directory_prefix)
        pages  = page_entries["pages"]
        pages += page_entries["sidebars"].values if page_entries["sidebars"].any?
        pages += page_entries["footers"].values  if page_entries["footers"].any?
        pages.each do |entry|
          page = GitHub::Unsullied::Page.new(wiki, entry)
          page.revision_oid = oid
          unique_pages[page.path] = page
        end

        unique_pages.each_value do |page|
          yield page
        end
      rescue ::GitRPC::BadRepositoryState, ::GitRPC::ObjectMissing, ::GitRPC::InvalidFullOid, ::GitRPC::NoSuchPath
      end

      # Internal: Check if this page is a special page.
      # Special pages start with a "_" character and currently include
      # "_Sidebar" and "_Footer".
      #
      # Returns true or false
      def special_page?(name)
        name =~ /^_/ ? true : false
      end

      # Internal: Check if `name` matches `page` given it's on-disk name.
      # `name` is checked against the on-disk filename of `page` by replacing
      # any of " ", "/", "<", ">" or "+" with a "-" character.
      # Upon page creation, any of the above characters in the page's name are
      # replaced with the "-" character.
      #
      # name - the name to check as a String
      # page - a Unsullied::Page used to check against
      #
      # Returns true or false
      def name_match?(name, page)
        basename = page.name
        ["_", "-"].each do |sub|
          if GitHub::Unsullied::Page.cname(name).downcase ==
             GitHub::Unsullied::Page.cname(basename, sub).downcase
            return true
          end
        end
        false
      end

      # Internal: Check the wiki repository for any pages that already exist
      # which match `name`.
      #
      # name - the name of the page to check for as a String
      #
      # Returns nothing, but raises Unsullied::Wiki::DuplicatePageError if a
      # duplicate was found.
      def check_for_duplicate(name)
        if page = find(name)
          stripped_name = GitHub::Unsullied::Page.bare_name(name)
          attempted = File.join(directory_prefix, stripped_name)

          raise GitHub::Unsullied::Wiki::DuplicatePageError, "Cannot create page, the name already exists."
        end
      rescue GitHub::DGit::UnroutedError
        # if the repo doesn't exist on disk yet, there aren't any duplicate pages
      end
    end
  end
end
