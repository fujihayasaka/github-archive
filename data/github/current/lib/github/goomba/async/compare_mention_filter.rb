# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class CompareMentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers
    SELECTOR = Goomba::Selector.new(match: "gh|compare-mention")

    def initialize(*args)
      super
      @compare_cache_nwo = {}
      @compare_cache_nwoless = {}
    end

    def selector
      SELECTOR
    end

    def async_scan
      Promise.all(@nodes.map do |node|
        nwo, base, head = node["nwo"], node["base"], node["head"]

        async_find_repository(nwo).then do |repo|
          next unless repo

          if !nwo
            cache_key = [base, head]
            Platform::Loaders::ExpandedGitCommitOid.load_all(repo, [base, head]).then do |full_base, full_head|
              if full_base && full_head
                @compare_cache_nwoless[cache_key] = {
                  base: full_base,
                  head: full_head,
                }
              end
            end
          else
            cache_key = [nwo, base, head]
            Platform::Loaders::ActiveRecordAssociation.load(repo, :owner).then do
              @compare_cache_nwo[cache_key] = {
                repo: repo,
              }
            end
          end
        end
      end)
    end

    def call(node)
      nwo, base, head, fragment, autolink = node["nwo"], node["base"], node["head"], node["fragment"], node["autolink"]
      if !nwo
        cache_key = [base, head]
        if details = @compare_cache_nwoless[cache_key]
          url = [repo_url, "compare", "#{details[:base]}...#{details[:head]}"].join("/")

          link_content = ActionController::Base.helpers.content_tag(:tt, "#{details[:base][0, 7]}...#{details[:head][0, 7]}")
          link = ActionController::Base.helpers.link_to(link_content, url, class: "commit-link")

          repository_reference_wrapper(repository, check_type: :contents) do |wrapper|
            wrapper.authorized { link }
            wrapper.unauthorized { "#{base}...#{head}" }
          end
        else
          "#{base}...#{head}"
        end
      else
        cache_key = [nwo, base, head]
        if details = @compare_cache_nwo[cache_key]
          points = [base, head].map do |point|
            if point =~ /\A[0-9a-f]{7,40}([~^].*)?\z/
              "#{point[0, 7]}#{$1}"
            else
              point
            end
          end

          repo = details[:repo]
          repo_nwo = repo.name_with_display_owner
          this_repo = repo == repository
          url = [repo_url(repo_nwo), "compare", "#{base}...#{head}"].join("/")
          nwo_text = (this_repo ? "" : "#{repo_nwo}@")

          text = "#{Addressable::URI.unescape(points[0])}...#{Addressable::URI.unescape(points[1])}".dup.force_encoding("utf-8").scrub!
          link_content = EscapeHelper.safe_join([nwo_text, ActionController::Base.helpers.content_tag(:tt, text), fragment])
          link = ActionController::Base.helpers.link_to(link_content, "#{url}#{fragment}", class: "commit-link")

          repository_reference_wrapper(repo, check_type: :contents) do |wrapper|
            wrapper.authorized { link }
            wrapper.unauthorized do
              if autolink
                ActionController::Base.helpers.link_to(Addressable::URI.unescape(autolink).force_encoding("utf-8").scrub!, autolink)
              else
                "#{base}...#{head}"
              end
            end
          end
        else
          ActionController::Base.helpers.link_to(Addressable::URI.unescape(autolink).force_encoding("utf-8").scrub!, autolink)
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
  end
end
