# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class CommitMentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers
    SELECTOR = Goomba::Selector.new(match: "gh|commit-mention")

    def initialize(*args)
      super
      @commit_cache_nwo = {}
      @commit_cache_nwoless = {}
    end

    def selector
      SELECTOR
    end

    def self.cache_key(context)
      GitHub::HTML::CommitMentionFilter.cache_key(context)
    end

    def async_scan
      Promise.all(@nodes.map do |node|
        nwo, sha = node["nwo"], node["sha"]

        async_find_repository(nwo).then do |repo|
          next unless repo

          if !nwo
            cache_key = [sha]
            if context[:expanded_shas]
              if (full_oid = context[:expanded_shas][sha])
                @commit_cache_nwoless[cache_key] = {
                  full_oid: full_oid,
                }
              end
            else
              Platform::Loaders::ExpandedGitCommitOid.load(repo, sha).then do |full_oid|
                if full_oid
                  @commit_cache_nwoless[cache_key] = {
                    full_oid: full_oid,
                  }
                end
              end
            end
          else
            cache_key = [nwo, sha]
            Platform::Loaders::ActiveRecordAssociation.load(repo, :owner).then do
              @commit_cache_nwo[cache_key] = { full_oid: sha, repo: repo }
            end
          end
        end
      end)
    end

    def call(node)
      nwo, sha, path, autolink = node["nwo"], node["sha"], node["path"], node["autolink"]
      if !nwo
        cache_key = [sha]
        if details = @commit_cache_nwoless[cache_key]
          url = [repo_url, "commit", details[:full_oid]].join("/")
          link_content = ActionController::Base.helpers.content_tag(:tt, GitHub::HTML::CommitMentionFilter.trimmed_commit_sha(details[:full_oid]))
          link = ActionController::Base.helpers.link_to(link_content, url, class: "commit-link", data: HovercardHelper.hovercard_data_attributes_for_commit(commit_url: url))

          repository_reference_wrapper(repository, check_type: :contents) do |wrapper|
            wrapper.authorized { link }
            wrapper.unauthorized { sha }
          end
        else
          sha
        end
      else
        cache_key = [nwo, sha]
        if details = @commit_cache_nwo[cache_key]
          repo = details[:repo]
          url = [repo_url(repo.name_with_display_owner), "commit", details[:full_oid]].join("/") + path.to_s
          nwo_text = normalize_nwo(repo, autolink: !!autolink)
          link_content = [nwo_text, ActionController::Base.helpers.content_tag(:tt, GitHub::HTML::CommitMentionFilter.trimmed_commit_sha(details[:full_oid])), path]
          # Don't show a hovercard if we're linking to an annotation, diff, or file within a commit
          hovercard_data_attrs = path.present? ? {} : HovercardHelper.hovercard_data_attributes_for_commit(commit_url: url)
          link = ActionController::Base.helpers.link_to(EscapeHelper.safe_join(link_content), url, class: "commit-link", data: hovercard_data_attrs)

          repository_reference_wrapper(repo, check_type: :contents) do |wrapper|
            wrapper.authorized { link }
            wrapper.unauthorized do
              if autolink
                ActionController::Base.helpers.link_to(autolink, autolink)
              else
                "#{nwo}@#{sha}"
              end
            end
          end
        elsif autolink
          ActionController::Base.helpers.link_to(autolink, autolink)
        else
          "#{nwo}@#{sha}"
        end
      end
    end

    def repo_url(name = nil)
      if name.blank?
        [GitHub.urls.url.chomp("/"), repository.name_with_display_owner].join("/")
      elsif name.include?("/")
        [GitHub.urls.url.chomp("/"), name].join("/")
      else
        # user@SHA - assume same repo name but different user
        [GitHub.urls.url.chomp("/"), name, repository.name].join("/")
      end
    end

    def normalize_nwo(repo, autolink:)
      return "" if repo == repository

      # owner is preloaded in the async_scan stage so this is safe
      prefix = repo.name_with_display_owner

      if autolink && repository && repo.source_id == repository.source_id
        prefix = repo.owner.display_login
      end

      "#{prefix}@"
    end
  end
end
