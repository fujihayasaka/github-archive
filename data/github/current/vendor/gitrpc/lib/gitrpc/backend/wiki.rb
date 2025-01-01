# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    MAX_WIKI_FILES  = 5000
    WIKI_SIDEBAR    = /\_sidebar/i
    WIKI_FOOTER     = /\_footer/i
    VALID_WIKI_PAGE = /^(.+)\.(md|mkdn?|mdown|markdown|textile|rdoc|org|creole|re?st(\.txt)?|asciidoc|pod|(media)?wiki)$/i

    rpc_reader :read_wiki_pages
    def read_wiki_pages(oid, directory_prefix)
      pages = {"pages" => [], "sidebars" => {}, "footers" => {}}

      # temporary to prevent race-condition errors on deploy
      pages["sidebar"] = pages["footer"] = nil

      res = read_tree_entries_recursive(oid, directory_prefix, MAX_WIKI_FILES)
      res["entries"].select do |entry|
        filename = ::File.basename(entry["path"])
        if entry["type"] == "blob" && GitRPC::Backend.valid_wiki_page?(filename)
          dirname = wiki_dirname(entry["path"])
          if wiki_sidebar?(filename)
            pages["sidebars"][dirname] = entry
          elsif wiki_footer?(filename)
            pages["footers"][dirname] = entry
          else
            pages["pages"] << entry
          end
        end
      end

      pages
    end

    # private

    def wiki_dirname(filename)
      dirname = File.dirname(filename)
      dirname = "" if dirname == "."
      dirname
    end

    def self.valid_wiki_page?(filename)
      filename =~ VALID_WIKI_PAGE
    end

    def wiki_sidebar?(filename)
      filename =~ WIKI_SIDEBAR
    end

    def wiki_footer?(filename)
      filename =~ WIKI_FOOTER
    end
  end
end
