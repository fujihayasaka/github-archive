# typed: true
# frozen_string_literal: true

module GitHub
  # WARNING: This is *not* for production use (aside from script/console).
  module Resources
    extend self

    class ProductionUseNotAllowedError < StandardError
      def message
        <<~MESSAGE
          GitHub::Resources.find_by_uri is only meant for usage by Rails
          console for debugging, please do not use it for production code
        MESSAGE
      end
    end

    # Public: Returns a Repository found by the name with owner.
    def with_name_with_owner(name_with_owner)
      Repository.with_name_with_owner(name_with_owner) ||
        RepositoryRedirect.find_redirected_repository(name_with_owner)
    end
    alias_method :nwo, :with_name_with_owner

    # Public: Finds a public-facing resource by URI, usually the URL.
    #
    # user     = the 'defunkt'
    # user     = the 'chris@github.com'
    # business = the 'acme-corp'
    # team     = the 'github/brunch'
    # team     = the '@github/brunch'
    # repo     = the 'defunkt/dotjs'
    # pr       = the 'github/gist/pull/123'
    # issue    = the 'github/gist/issues/123'
    # issue    = the 'github/gist#123'
    # entry    = the 'github/github/blob/master/Blakefile'
    def find_by_uri(str, suppress_warning: false)  # rubocop:disable GitHub/FindByDef
      if Rails.env.test? && !suppress_warning
        Kernel.raise ProductionUseNotAllowedError
      end

      str = str.to_s.strip
      case str
      # github/gist/issues/123 or github/gist/pull/123 or github/gist#123
      when %r{^([^/]+/[^/#]+)(?:/pull/|/issues/|#)(\d+)$}
        return unless repo = with_name_with_owner($1)
        subject = repo.issues.find_by_number($2) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        if subject&.pull_request?
          subject = subject.pull_request
        end
        subject
      # orgs/github/discussions/1
      when %r{\Aorgs\/([^\/]+)(?:/discussions/)(\d+)\z}
        return unless org = Organization.find_by(login: $1)
        return unless repo = org.discussion_repository&.repository
        Discussion.for_repository(repo).with_number($2).first
      # github/gist/discussions/1
      when %r{^([^/]+/[^/#]+)(?:/discussions/)(\d+)$}
        return unless repo = with_name_with_owner($1)
        Discussion.for_repository(repo).with_number($2).first
      # github/gist/commit/decafbad
      when %r{^([^/]+/[^/#]+)(?:/commit/|@)([0-9a-f]+)$}
        with_name_with_owner($1).commits.find_for_sha($2)
      # github/gist/pull/5/commits/decafbad
      when %r{\A([^/]+/[^/#]+)(?:/pull/\d+/commits/)([0-9a-f]+)\z}
        with_name_with_owner($1).commits.find_for_sha($2)
      # github/gist/compare/decafbad...master
      when %r{^([^/]+/[^/#]+)(?:/compare/|@)(\S+(?:\.{3}\S+)?)$}
        GitHub::Comparison.from_range_or_ref(with_name_with_owner($1), $2, user: User.ghost)
      # github/github/blob/master/Blakefile
      # github/github/tree/master/lib
      when %r{^([^/]+/[^/#]+)/(blob|tree)/(.+)$}
        repo = with_name_with_owner($1)
        rest = Addressable::URI.unescape($3)
        committish, path = RefShaPathExtractor.new(repo).call(rest)
        oid = repo.ref_to_sha(committish)
        case $2
        when "blob"
          repo.blob(oid, path)
        when "tree"
          begin
            Directory.new(repo, oid, path).tap do |dir|
              dir.tree_entries
            end
          rescue ::GitRPC::NoSuchPath
          end
        end
      # orgs/github/teams/employees
      when %r{^orgs/([^/]+)/teams/([^/]+)}
        Team.with_org_name_and_slug($1, $2)
      # github/github (org/entity) or github/security (org/team)
      # or @github/security (@org/team)
      when %r{^(@?)([^/]+)/([^/]+)$}
        if $1.present?
          Team.with_org_name_and_slug($2, $3)
        else
          with_name_with_owner(str) || Gist.with_name_with_owner(str) || Team.with_org_name_and_slug($2, $3)
        end
      # Email address
      when /@/
        User.find_by_email(str)
      # a URL
      when URI.regexp
        uri = URI.parse(str)
        case
        # https://github.com/mtodd/test/issues/5#issuecomment-15792290
        when uri.fragment =~ /issuecomment-(\d+)/
          IssueComment.find($1)
        # https://github.com/github/github/pull/10415#discussion_r3625405
        when uri.fragment =~ /discussion_r(\d+)/
          PullRequestReviewComment.find($1)
        # https://github.com/github/github/commit/e80e6333fc4d30a185c1578465b1756edc11a5bd#commitcomment-2929895
        when uri.fragment =~ /commitcomment-(\d+)/
          CommitComment.find_by(id: $1)
        # https://gist.github.com/lerebear/03220dbb889403e7d7603dd822917389#gistcomment-2904429
        when uri.fragment =~ /gistcomment-(\d+)/
          GistComment.find_by(id: $1)
        # https://github.com/github/discussions/discussions/107#discussioncomment-115
        when uri.fragment =~ /#{DiscussionComment::DOM_ID_PREFIX}(\d+)/
          DiscussionComment.find_by(id: $1)
        # https://github.com/github-linguist/linguist/releases/tag/v4.2.5
        when uri.path =~ %r{^/([^/]+/[^/#]+)/releases/tag/(.+)$}
          repo = with_name_with_owner($1)
          repo.releases.find_by_tag_name($2)
        when uri.to_s.start_with?("#{GitHub.gist_url}/")
          path = uri.path
          return unless path.present?
          repo_name = path.split("/")[-1]
          Gist.find_by(repo_name: repo_name)
        # https://github.com/enterprises/acme-corp
        when uri.path =~ %r{\A/enterprises/(.+)\z}
          Business.find_by(slug: $1)
        # try without the host
        else
          path = uri.path
          return unless path.present?
          find_by_uri(path.delete_prefix("/"), suppress_warning: true)
        end
      # Just a username/slug
      else
        User.find_by_login(str) || Business.find_by(slug: str)
      end
    end
    alias_method :find_by_url, :find_by_uri
    alias_method :the, :find_by_uri
    alias_method :dat, :find_by_uri

    # Public: Get a url for a model.
    #
    # model - Instance of a model
    #
    # Returns a String.
    def url_for_model(model)
      UrlForModel.new(model).url
    end

    class UrlForModel
      include UrlHelpers

      def default_url_options
        uri = URI.parse(GitHub.url)

        { host: uri.host, protocol: uri.scheme }
      end

      class NotImplemented < StandardError; end

      def initialize(model)
        @model = model
      end

      attr_reader :model

      def url
        return unless model

        case model
        when Repository
          repository_url(model.owner, model)
        when User
          user_url(model)
        when Label
          label_url(model.repository.owner, model.repository, model)
        when Milestone
          milestone_query_url(model.repository.owner, model.repository, model.title)
        when Issue
          issue_url(model.repository.owner, model.repository, model)
        when PullRequest
          show_pull_request_url(model.repository.owner, model.repository, model)
        when IssueComment
          if pull_request = model.issue.pull_request
            show_pull_request_url(pull_request.repository.owner, pull_request.repository, pull_request, anchor: "issuecomment-#{model.id}")
          else
            issue_url(model.repository.owner, model.repository, model.issue, anchor: "issuecomment-#{model.id}")
          end
        when PullRequestReviewComment
          # there is no route helper for the files tab of pull requests, the
          # only thing I found related was this: https://github.com/github/github/blob/c8e0d3e74887745cf585d7d4371c9d8435c617b8/app/views/pull_requests/_tabs.html.erb#L51
          pr_url = show_pull_request_url(model.repository.owner, model.repository, model.pull_request)
          pr_url += "/files#r#{model.id}"
          pr_url
        when CommitComment
          commit_url(model.repository.owner, model.repository, model.commit_id, anchor: "commitcomment-#{model.id}")
        when IssueEvent
          if pull_request = model.issue.pull_request
            show_pull_request_url(pull_request.repository.owner, pull_request.repository, pull_request, anchor: "event-#{model.id}")
          else
            issue_url(model.repository.owner, model.repository, model.issue, anchor: "event-#{model.id}")
          end
        when Team
          team_url(model.organization, model)
        else
          raise NotImplemented.new("not implemented for #{model.class.try(:model_name) || model.class.name}")
        end
      end
    end
  end
end
