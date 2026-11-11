# typed: true
# frozen_string_literal: true
require "rinku"

module HTML
  class Pipeline
    # HTML Filter for auto_linking urls that belong to valid domains and subdomains
    # for linkified annotations.
    #
    # Context options:
    #   :autolink  - boolean whether to autolink urls
    #   :link_attr - HTML attributes for the link that will be generated
    #   :skip_tags - HTML tags inside which autolinking will be skipped.
    #                See Rinku.skip_tags
    #   :flags     - additional Rinku flags. See https://github.com/vmg/rinku
    #
    # This filter does not write additional information to the context.
    class ActionsAnnotationAutolinkFilter < Filter
      GITHUB_REGEX = %r{
        (                                     # start capturing group, needed for splitting
        https:\/\/                            # must be https to be linkified
        (?:(?:docs\.)|(?:support\.))?         # only match docs, support or no subdomain
        (?:#{GitHub.host_name.sub(".", "\.")} # match github domain in use
        |github\.com                          # or github.com
        |githubstatus\.com                    # or our status page
        |github\.blog)                        # or our blog
        (?:\/[-a-zA-Z\d%_.~+]*)*              # match path
        (?:\?[;&a-zA-Z\\d%_.~+=-]*)?          # match query string
        (?:[\w#-_])*                          # match document fragments
        )                                     # end capturing group
      }x

      def call
        return html if context[:autolink] == false

        skip_tags = context[:skip_tags]
        flags = 0
        flags |= context[:flags] if context[:flags]

        github_links = html.split(GITHUB_REGEX)
        return html if github_links.length == 1

        chunk_array = []
        github_links.each do |chunk|
          # only auto link github.com, docs.github.com, support.github.com, github.blog, and githubstatus.com
          if chunk.match(GITHUB_REGEX)
            chunk = Rinku.auto_link(chunk, :urls, 'class="link-gray" rel="noreferrer noopener" data-test-selector="linkified"', skip_tags, flags)
          end
          chunk_array << chunk
        end

        chunk_array.join
      end
    end

  end
end
