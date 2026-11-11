# typed: false
# frozen_string_literal: true

# rubocop:disable Primer/PrimerOcticon

module GitHub
  module Unsullied
    class Page
      include ActionView::Helpers::TagHelper
      include OcticonsHelper

      WIKI_SIDEBAR    = /\_sidebar/i
      WIKI_FOOTER     = /\_footer/i
      VALID_WIKI_PAGE = /^(.+)\.(md|mkdn?|mdown|markdown|textile|rdoc|org|creole|re?st(\.txt)?|asciidoc|pod|(media)?wiki)$/i
      private_constant :WIKI_SIDEBAR, :WIKI_FOOTER, :VALID_WIKI_PAGE

      # The Unsullied::Wiki object this collection is wrapping
      attr_reader :wiki

      # The revision oid (as a 40 character String) this page was looked up from
      attr_accessor :revision_oid

      def initialize(wiki, info)
        @wiki = wiki
        @info = info
        @path = info["path"].dup
        @path.force_encoding("UTF-8").scrub!
      end

      # The GitRPC object used to perform all git operations
      delegate :rpc, to: :wiki

      # Public: The title of this wiki page
      #
      # Returns a String like "Some Page" assuming filename was "Some-Page.md"
      def title
        name_stripped.strip
      end

      # Public: The name of this wiki page
      #
      # Returns a String like "Some-Page" assuming filename was "Some-Page.md"
      def name
        self.class.bare_name(@path)
      end

      # Public: The name of this wiki, stripped of any "-" characters
      #
      # Returns a String like "Some Page" assuming filename was "Some-Page.md"
      def name_stripped
        self.class.stripped_name(@path)
      end
      # TODO: Remove this. It's here for compatibility with Gollum, for now.
      alias_method :filename_stripped, :name_stripped

      # Public: The filename of this page
      #
      # Returns a String like "Some-Page.md"
      def filename
        ::File.basename(@path)
      end

      # Public: The full path of this page, suitable for display.
      # Encoding: UTF-8, scrubbed
      #
      # Returns a String like "/some/dir/Some-Page.md"
      def path
        @path
      end

      # Public: The full path of this page returned from git, encoded as
      # ASCII-8BIT.  Use this to link to a page, or find a page in a hash.
      #
      # Returns a String like "/some/dir/Some-Page.md"
      def raw_path
        @info["path"]
      end

      # Public: The parent directory name of this page
      #
      # Returns a String like "/some/dir" or "" if it's the root directory
      def dirname
        dirname = File.dirname(path)
        dirname = "" if dirname == "."
        dirname
      end

      # Public: Returns the renderable format name for this page based on it's
      # extension.
      #
      # Returns a Symbol like :markdown if the extension is ".md"
      def format
        case ::File.extname(filename)
        when /\.(md|mkdn?|mdown|markdown)\z/i
          :markdown
        when /\.(textile)\z/i
          :textile
        when /\.(rdoc)\z/i
          :rdoc
        when /\.(org)\z/i
          :org
        when /\.(creole)\z/i
          :creole
        when /\.(re?st(\.txt)?)\z/i
          :rest
        when /\.(asciidoc)\z/i
          :asciidoc
        when /\.(pod)\z/i
          :pod
        when /\.(\d)\z/i
          :roff
        when /\.(media)?wiki\z/i
          :mediawiki
        else
          nil
        end
      end

      # Public: The raw content of this page.
      # The content itself may be in any supported Ruby encoding. This method
      # won't attempt any transcoding. If you want it as UTF-8 use `data_utf8`
      # instead.
      #
      # Returns the content of the page as a String
      def data
        @info["data"] || load_data["data"]
      end

      # Public: The raw content of this page transcoded into UTF-8.
      # If the content's encoding was detected by the GitRPC backend, that's
      # the encoding that will be used to transcode from when going to UTF-8.
      # If no encoding was detected this method will scrub the content of any
      # invalid UTF-8 sequences. Ensuring the return value is always valid
      # UTF-8.
      #
      # Returns the content of the page as a valid UTF-8 String.
      def data_utf8
        return unless data

        @data_utf8 ||= if @info["encoding"]
          ::GitHub::Encoding.transcode(data, @info["encoding"], "UTF-8")
        else
          data.dup.force_encoding("UTF-8").scrub
        end
      end

      def deleted?
        @info["modified_status"] == "D"
      end

      # Public: The contents of the page rendered into HTML.
      # The contents of the page are transcoded to UTF-8 before being used for
      # rendering.
      #
      # context - the context (options) to be passed to the HTML pipeline for
      #           render.
      #
      # Returns the rendered version of this page in HTML as a String, and
      # tagged as html safe.
      def data_html(context = {})
        return if data.nil?

        context = context.merge({
          entity: self.wiki,
          page: self,
          path: path,
          format: format,
          anchor_icon: octicon("link"),
        })

        rendered = DataHtml.new
        start = GitHub::Dogstats.monotonic_time
        begin
          Timeout.timeout 5 do
            result = ::GitHub::Goomba::WikiPipeline.call(data_utf8, context)
            ::GitHub.dogstats.timing_since("wiki.process.#{format}.success", start)
            rendered.toc = result[:toc_headers_hash] || []
            result[:output].gsub!("<p></p>", "")
            rendered.html = GitHub::HTML::Result.to_html(result)
          end
        rescue => error # rubocop:todo Lint/RescueException
          ::GitHub.dogstats.timing_since("wiki.process.#{format}.error", start)
          rendered.error = error.is_a?(Timeout::Error) ? :_timeout : error.to_s
          rendered.html = content_tag(:p, "Sorry, there was an error rendering this page.")

          Failbot.report(error) unless rendered.timed_out?
        end

        rendered
      end

      # Public: Represents the result of rendering a Page, potentially with an error.
      DataHtml = Struct.new(:html, :toc, :error)

      class DataHtml
        def errored?
          error.present?
        end

        def timed_out?
          errored? && error == :_timeout
        end

        alias to_s html

        PACKER = lambda do |obj|
          GitHub::Cache::Codec.factory.pack({
            html: GitHub::Cache::SafeBuffer.new(obj.html),
            toc: GitHub::Cache::SafeBuffer.new(obj.toc),
            error: obj.error,
          })
        end

        UNPACKER = lambda do |data|
          hash = GitHub::Cache::Codec.factory.unpack(data)
          GitHub::Unsullied::Page::DataHtml.new(hash[:html], hash[:toc], hash[:error])
        end

        GitHub::Cache::Codec.register_type(
          GitHub::Cache::Codec::UNSULLIED_PAGE_DATA_HTML_TYPE,
          self)
      end

      # Public: The summary of the last commit message used for this page
      #
      # Returns a String
      def summary
        lines = latest_revision.message.split(/\n/)
        return nil if lines.size == 1
        lines.pop
        lines.join("\n").strip
      end

      # Public: Generate a diff between two commits for this page.
      #
      # commit_oid1 - an oid as a 40 character String. Specify nil to use
      #               commit_oid2's parent commit.
      # commit_oid2 - an oid as a 40 character String.
      #
      # Returns a GitHub::Diff object
      def diff(commit_oid1, commit_oid2)
        commit_oid1 = wiki.spokes_api.resolve_object(object_name: commit_oid1) if commit_oid1
        commit_oid2 = wiki.spokes_api.resolve_object(object_name: commit_oid2) if commit_oid2

        if commit_oid1.nil?
          commit_data = wiki.read_objects(
            [commit_oid2],
            :commit
          )
          commit_oid1 = commit_data.first["parents"].first
        end

        diff_opts = { paths: [path] }
        ::GitHub::Diff.new(wiki, commit_oid1, commit_oid2, diff_opts)
      rescue ::GitRPC::BadRepositoryState
      end

      # Public: A list of revisions for this page.
      #
      # offset - the offset of which to start listing revisions
      # limit  - the number of revisions to return
      #
      # Returns an array of Commit objects
      def revisions(offset = 0, limit = 30)
        oids = rpc.list_revision_history(wiki.default_oid, {
          "offset" => offset,
          "limit"  => limit,
          "path"   => path,
        })

        commits.find(oids)
      end

      # Public: The number of revisions for this page.
      #
      # oid - the oid (as a 40 character String) of which to start counting
      #       revisions from
      #
      # Returns an Integer or nil if the counting operation failed
      def revision_count(oid = wiki.default_oid)
        rpc.count_revision_history(oid, path: path)
      rescue GitRPC::CommandFailed
        nil
      end

      # Public: Get the most recent revision for this page.
      #
      # oid - the oid (as a 40 character String) of the wiki for which to start
      #       looking for the most recent revision that touches this page.
      #
      # Returns a Commit object or nil if the page didn't exist yet as of `oid`
      def latest_revision(oid = revision_oid || wiki.default_oid)
        # sometimes, wiki.latest_revisions does not include all the files in the wiki repo
        # so we try that first and then fall back to getting the latest_oid for this page
        # individually
        pages = wiki.latest_revisions(oid)
        unless pages.key?(raw_path)
          pages = wiki.blame_tree(oid, raw_path, false)
        end
        if latest_oid = pages[raw_path]
          commits.find(latest_oid)
        end
      end

      # Public: The sidebar for this wiki page
      # Sidebars are named "_Sidebar" with any supported markup extension wikis
      # support. They are looked up by starting in the same directory as this
      # page, then walking backwards up to `directory_prefix` until one is
      # found. This is so the user can have page-specific sidebars that will be
      # used when viewing a specific page.
      #
      # oid - the revision oid (as a 40 character String) to attempt to lookup
      #       the sidebar from.
      #
      # Returns an Unsullied::Page object or nil if no sidebar could be found.
      def sidebar(oid = wiki.default_oid)
        entries = wiki.read_wiki_pages(oid, wiki.directory_prefix)
        dirs = path.split("/")
        dirs.pop

        sidebar = nil
        sidebars = entries["sidebars"]
        while !dirs.empty?
          if page = sidebars[dirs.join("/")]
            sidebar = page
            break
          end
          dirs.pop
        end

        if sidebar
          GitHub::Unsullied::Page.new(wiki, sidebar)
        elsif sidebar = sidebars[wiki.directory_prefix]
          GitHub::Unsullied::Page.new(wiki, sidebar)
        end
      end

      # Public: The footer for this wiki page
      # Footers are named "_Footer" with any supported markup extension wikis
      # support. They are looked up by starting in the same directory as this
      # page, then walking backwards up to `directory_prefix` until one is
      # found. This is so the user can have page-specific footers that will be
      # used when viewing a specific page.
      #
      # oid - the revision oid (as a 40 character String) to attempt to lookup
      #       the footer from.
      #
      # Returns an Unsullied::Page object or nil if no footer could be found.
      def footer(oid = wiki.default_oid)
        entries = wiki.read_wiki_pages(oid, wiki.directory_prefix)
        dirs = path.split("/")
        dirs.pop

        footer = nil
        footers = entries["footers"]
        while !dirs.empty?
          if page = footers[dirs.join("/")]
            footer = page
            break
          end
          dirs.pop
        end

        if footer
          GitHub::Unsullied::Page.new(wiki, footer)
        elsif footer = footers[wiki.directory_prefix]
          GitHub::Unsullied::Page.new(wiki, footer)
        end
      end

      # Public: The timestamp for the last time this page was updated
      def updated_at
        latest_revision.authored_date
      end

      # Internal: The URL-friendly name of this page
      #
      # Returns a String
      def to_param
        self.class.to_param(path)
      end

      # Public: Update this page. By either changing it's name, contents, format
      # or all of that.
      #
      # new_name    - the new or existing name for this page
      # data        - the new or existing content for this page
      # new_format  - the new or existing renderable format for this page
      # message     - the message used for the commmit created while updating
      #               this page in the wiki repository
      # user        - the User object to use as the committer
      #
      # Returns an Unsullied::Page representing the updated page
      def update(new_name, data, new_format, message, user)
        self.class.prevent_unwanted_edit!(wiki: wiki, user: user, operation: :edit)

        if !user.has_primary_email?
          raise GitHub::Unsullied::Wiki::Error, "User has no primary email address"
        end

        new_name = name if new_name.blank?
        new_name = self.class.treat_special_characters_for_saving(new_name)
        new_format = format if new_format.blank?

        new_filename = self.class.make_filename(new_name, new_format)
        check_for_renamed_duplicate(new_filename)

        if message.blank?
          fmt_msg = if format != new_format
            "#{format} => #{new_format}"
          else
            format
          end
          message = "Updated #{title} (#{fmt_msg})"
        end

        parents = [wiki.default_oid]
        info = {
          "message"   => message,
          "committer" => {
            "name"  => user.git_author_name,
            "email" => user.git_author_email,
            "time"  => Time.zone.now.iso8601,
          },
        }

        data = GitHub::Unsullied::Page.normalize_newlines(data, self.data)
        data = { "data" => data }
        files = {}
        if rename?(new_filename)
          files[path] = nil
          files[new_filename] = data
        else
          files[path] = data
        end

        oid = rpc.create_tree_changes(parents, info, files)
        wiki.update_default_ref(oid, user: user)

        if FeatureFlag.vexi.enabled?(:wiki_attachment_scanning, default: true)
          self.class.attach_matching_assets(wiki, data["data"], user)
        end

        wiki.pages.find(new_name, oid)
      end

      # Public: Remove this page from the wiki repo.
      #
      # user    - the User object used as the committer
      # message - (optional) the commit message String
      #
      # Returns the oid of the newly created commit which removed this page.
      def remove(user, message = nil)
        self.class.prevent_unwanted_edit!(wiki: wiki, user: user, operation: :delete)

        if !user.has_primary_email?
          raise GitHub::Unsullied::Wiki::Error, "User has no primary email address"
        end

        parents = [wiki.default_oid]
        if message.blank?
          message = "Destroyed #{title} (#{format})"
        end

        info = {
          "message"   => message,
          "committer" => {
            "name"  => user.git_author_name,
            "email" => user.git_author_email,
            "time"  => Time.zone.now.iso8601,
          },
        }

        files = { path => nil }

        oid = rpc.create_tree_changes(parents, info, files)
        wiki.update_default_ref(oid, user: user)

        oid
      end

      # Public: Revert the changes that happened between `commit_oid1` and
      # `commit_oid2` for this page.
      #
      # commit_oid1 - a 40 character oid as a String
      # commit_oid2 - a 40 character oid as a String
      # user        - a User object used as the committer information for the
      #               revert commit
      #
      # Returns the oid of the newly created commit as a 40 character String
      def revert(commit_oid1, commit_oid2, user)
        self.class.prevent_unwanted_edit!(wiki: wiki, user: user, operation: :edit)

        if !user.has_primary_email?
          raise GitHub::Unsullied::Wiki::Error, "User has no primary email address"
        end

        message = "Revert #{commit_oid1}...#{commit_oid2} on #{self.title}"

        opts = {
          "path"    => self.path,
          "message" => message,
          "committer" => {
            "name"  => user.git_author_name,
            "email" => user.git_author_email,
            "time"  => Time.zone.now.iso8601,
          },
        }

        # TODO: Current oid should be a argument passed to revert
        oid = rpc.revert_range(commit_oid1, commit_oid2, opts)
        wiki.update_default_ref(oid, user: user)

        oid
      end

      # Public: Check if this page is the default (home) page for this wiki
      #
      # Returns true or false
      def default?
        name =~ /\A#{GitHub::Unsullied::PagesCollection::DEFAULT_PAGE_NAME}\z/i
      end

      # Public: The cache key for this wiki page
      #
      # Returns a String
      def cache_key
        version = "v12"
        [wiki.cache_key, version, hashed_filename, revision_oid].join(":")
      end

      # Internal: The URL-friendly name of a wiki page
      #
      # Returns a String
      def self.to_param(path)
        name = bare_name(path)
        cname(name)
      end

      # Internal: Check if `name` is a valid naem for a wiki page
      #
      # Returns true or false
      def self.valid_page_name?(name)
        name =~ VALID_WIKI_PAGE
      end

      # Internal: Check if `name` is a valid wiki sidebar page name.
      #
      # Returns true or false
      def self.wiki_sidebar?(name)
        name =~ WIKI_SIDEBAR
      end

      # Internal: Check if `name` is a valid wiki footer page name.
      #
      # Returns true or false
      def self.wiki_footer?(name)
        name =~ WIKI_FOOTER
      end

      # Internal: Get the canonical name for a wiki page.
      # This will strip any " ", "/", "<", ">" or "+" characters and replace
      # them with "-".
      #
      # Returns a String
      def self.cname(name, sub = "-")
        name.gsub(/[\s\/<>+]/, sub)
      end

      # Internal: The stripped name for a wiki page
      # This will replace any "-" characters with " ".
      #
      # Returns a String
      def self.stripped_name(name)
        bare_name(name).gsub("-", " ")
      end

      # Internal: The "bare name" for a wiki page.
      # This will strip the file extension from `name`.
      #
      # Returns a String
      def self.bare_name(name)
        ::File.basename(name, ::File.extname(name))
      end

      # Internal: Create a filename string from `name` and `format`.
      #
      # name   - the name of the wiki page as a String
      # format - the renderable format for the page as a Symbol, like :markdown
      #
      # Returns a String like "Some Page.md" if name is "Some Page" and format
      # is :markdown
      def self.make_filename(name, format)
        "#{name}.#{format_to_extension(format)}"
      end

      # Internal: Get the extension for a format name
      #
      # format - the renderable format name as a Symbol, like :markdown
      #
      # Returns a String like "md"
      def self.format_to_extension(format)
        case format.to_sym
        when :markdown  then "md"
        when :textile   then "textile"
        when :rdoc      then "rdoc"
        when :org       then "org"
        when :creole    then "creole"
        when :rest      then "rest"
        when :asciidoc  then "asciidoc"
        when :pod       then "pod"
        when :mediawiki then "mediawiki"
        end
      end

      # Internal: Helper function to normalize the newline characters in `data`.
      #
      # data     - the content to normalize
      # old_data - (optional) if passed, will be used to check if the newline
      #            format had changed
      #
      # Returns a String
      def self.normalize_newlines(data, old_data = nil)
        if old_data && old_data =~ encoded_crlf(old_data.encoding)
          data
        else
          data.gsub(encoded_crlf(data.encoding), "\n")
        end
      end

      # Internal: Get a Regex representing a crlf pair encoded in `encoding`
      #
      # Returns a Regex object
      def self.encoded_crlf(encoding)
        crlf = "\r\n".encode(encoding)
        /#{crlf}/
      end

      # Internal: The SHA256 of the path of this wiki page
      #
      # Returns a String
      def hashed_filename
        ::Digest::SHA256.hexdigest(path)
      end

      # Internal: An iterator for all of the commits in the wiki this page is
      # inside of.
      #
      # Returns a CommitsCollection object
      def commits
        @commits ||= ::CommitsCollection.new(wiki)
      end

      # Internal:
      def load_data
        return {} unless @info["oid"]

        @info.merge!(wiki.read_objects(
          [@info["oid"]], :blob).first)
      end

      # Internal: Check if a rename would conflict with an existing page in the
      # wiki.
      #
      # if the tree looks like this:
      # home.md
      # wassup.md
      #
      # we should prevent:
      # wassup.md -> home.md
      # wassup.md -> home.textile
      #
      # but allow:
      # wassup.md -> wassup.textile
      #
      # Returns nothing but will raise Unsullied::Wiki::DuplicatePageError if a
      # duplicate was found.
      def check_for_renamed_duplicate(new_filename)
        new_bare = self.class.bare_name(new_filename)
        new_cname = self.class.cname(new_bare)

        if rename?(new_filename) && page = wiki.pages.find(new_cname)
          if name != page.name
            raise GitHub::Unsullied::Wiki::DuplicatePageError, "Cannot rename, target already exists."
          end
        end
      end

      # Internal: Check if `new_filename` is different from the current name
      # of this page.
      #
      # Returns true or false
      def rename?(new_filename)
        new_cname = self.class.cname(new_filename)
        new_cname != filename && new_filename != filename
      end

      def self.attach_matching_assets(wiki, data, user)
        GitHub.dogstats.increment("attach_matching_assets.runs", tags: [
          "class:#{self.name.underscore}",
          "in_background:true"
        ])

        repository_wiki = RepositoryWiki.find_by(repository: wiki.repository)
        AttachMatchingAssetsJob.perform_later(repository_wiki, raw_data: data, attaching_user: user, detach_removed_assets: false)
      end

      def self.prevent_unwanted_edit!(wiki:, user:, operation: :edit)
        prevent_blocked_edit!(wiki, user)

        authorization = ContentAuthorizer.authorize(user, :wiki, operation, wiki: wiki)
        if authorization.failed?
          raise Unsullied::Wiki::UnwantedEditError,
            authorization.error_messages
        end
      end

      def self.prevent_blocked_edit!(wiki, user)
        if user.blocked_by?(wiki.repository.owner)
          raise Unsullied::Wiki::UnwantedEditError,
            "Users cannot edit repositories owned by users who have blocked them"
        end
      end

      def self.treat_special_characters_for_saving(name)
        # Invalid characters (and the space) are replaced with the ASCII hyphen when calling cname, which are later
        # stripped for the user by replacing them with spaces. To prevent this for user passed in hyphens, save them
        # as the unicode hyphen.
        name = name.gsub("-", "‐")
        name = cname(name)
      end
    end
  end
end
