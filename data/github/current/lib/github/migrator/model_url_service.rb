# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ModelUrlService
      class NotImplemented < MigrationError
        include ::GitHub::Migrator::MapWarning
      end

      def initialize(options = nil)
        @options = options || {}
        @cache   = @options[:cache] || Cache.null
      end

      # Public: Get a URL that represents the given model.
      #
      #   url_for_model(Repository.last)
      #   => "https://github.com/github/github"
      #   url_for_model(IssueComment.last)
      #   => "https://github.com/github/github/issues/123456#issuecomment-9876543"
      def url_for_model(model, use_cache: true)
        return unless model
        return uncached_internal_url_for_model(model) unless use_cache

        cache.getset("url_for_model:#{model.class.model_name.singular}:#{model.id}") do
          internal_url_for_model(model)
        end
      end

      # Public: Get a URL that represents the associated model.
      #
      #   url_for_association(Repository.last, :owner)
      #   => "https://github.com/github"
      def url_for_association(model, association_name)
        association = model.association(association_name)
        reflection = association.reflection
        cached_model_url(model_class: association.klass.name, model_id: model[reflection.foreign_key]) do
          if target = Platform::Loaders::ActiveRecordAssociation.load(model, reflection.name).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            uncached_internal_url_for_model(target)
          end
        end
      end

      # Public: Find a model given its URL.
      #
      #   model_for_url("https://github.com/github/github")
      #   => #<Repository name: "github", ...>
      def model_for_url(url)
        return unless url.present?

        cache.getset("model_for_url:#{url}") do
          internal_model_for_url(url)
        end
      end

      # Public: Determine whether a url is valid or not.
      #
      #   url_valid?("https://github.com/mattr-")
      #   => false
      #   url_valid?("https://github.com/mattr")
      #   => true
      def url_valid?(url)
        ModelForUrl.new(url, options).valid?
      end

      private

      attr_reader :cache, :options

      def internal_url_for_model(model)
        return unless model

        cached_model_url(model_class: model.class.name, model_id: model.id) do
          uncached_internal_url_for_model(model)
        end
      end

      def uncached_internal_url_for_model(model)
        case model
        when Repository
          url = url_for_association(model, :owner)
          File.join(url, model.name) if url.present?
        when ProtectedBranch
          File.join(url_for_association(model, :repository), "settings", "branches", UrlHelper.escape_path(model.name))
        when Mannequin
          File.join(GitHub.url, model.source_login)
        when User
          model.ghost? ? nil : File.join(GitHub.url, model.display_login)
        when Label
          File.join(url_for_association(model, :repository), "labels", UrlHelper.escape_path(model.name))
        when Milestone
          File.join(url_for_association(model, :repository), "milestones", model.number.to_s)
        when Project
          File.join(url_for_association(model, :owner), "projects", model.number.to_s)
        when Issue
          url_for_association(model, :pull_request) ||
            File.join(url_for_association(model, :repository), "issues", model.number.to_s)
        when PullRequest
          File.join(url_for_association(model, :repository), "pull", model.number.to_s)
        when IssueComment
          url_for_association(model, :issue) + "#issuecomment-#{model.id}"
        when PullRequestReview
          url_for_association(model, :pull_request) + "/files#pullrequestreview-#{model.id}"
        when PullRequestReviewThread
          url_for_association(model, :pull_request) + "/files#pullrequestreviewthread-#{model.id}"
        when PullRequestReviewComment
          url_for_association(model, :pull_request) + "/files#r#{model.id}"
        when CommitComment
          File.join(url_for_association(model, :repository), "commit", model.commit_id) + "#commitcomment-#{model.id}"
        when IssueEvent
          url_for_association(model, :issue) + "#event-#{model.id}"
        when Team
          org_url = url_for_association(model, :organization)
          (org_url.sub(%r{/[^/]+\z}) { |name| "/orgs#{name}" }) + "/teams/" + UrlHelper.escape_path(model.slug)
        when Release
          File.join(url_for_association(model, :repository), "releases", "tag", model.tag_name)
        when Attachment
          model.asset&.storage_external_url
        when RepositoryFile
          model.storage_external_url
        when Discussion
          url_for_association(model, :repository) + "/discussions/#{model.number}"
        when DiscussionComment
          url_for_association(model, :discussion) + "#discussioncomment-#{model.id}"
        when DiscussionCategory
          File.join(url_for_association(model, :repository), "discussion_categories", UrlHelper.escape_path(model.name))
        when DiscussionComment
          url_for_association(model, :discussion) + "##{model.dom_id}"
        when RepositoryAdvisory
          File.join(url_for_association(model, :repository), "security", "advisories", model.ghsa_id)
        else
          raise NotImplemented.new("not implemented for #{model.class.try(:model_name) || model.class.name}")
        end
      end

      def cached_model_url(model_class:, model_id:)
        cache.getset("cached_model_url:#{model_class}:#{model_id}") do
          yield
        end
      end

      def internal_model_for_url(url)
        ModelForUrl.new(url, options).model
      end
    end

    class ModelForUrl
      class NotImplemented < StandardError; end

      def initialize(url, options = nil)
        @url = url
        options = options || {}
        @cache = options[:cache] || Cache.null
      end

      # Public: The url passed in at initialization.
      #
      # Returns a String.
      attr_reader :url

      attr_reader :cache

      # Public: Get the model represented by the url.
      #
      # Returns an instance of Repository, User, Organization...
      def model
        return team if team_url?
        return user if user_url?
        return bot if bot_url?
        return repo if repo_url?
        return project if project_url?
        return comment_thread_or_event if comment_thread_or_event_url?
        return issue_pull_discussion_label_or_milestone if issue_pull_discussion_label_or_milestone_url?
        return release if release_url?
        return repository_advisory if repository_advisory_url?
        return old_user_asset if old_user_asset_url?
        return new_user_asset if new_user_asset_url?
        return old_repository_file if old_repository_file_url?
        return new_repository_file if new_repository_file_url?

        raise NotImplemented.new("not implemented for \"#{scrub_url(url)}\"")
      end

      def valid?
        return true if team_url?
        return valid_user_url? if user_url?
        return true if repo_url?
        return true if comment_thread_or_event_url?
        return true if issue_pull_discussion_label_or_milestone_url?
        return true if release_url?
        return true if project_url?
        return true if repository_advisory_url?
        return true if old_user_asset_url?
        return true if new_user_asset_url?
        return true if old_repository_file_url?
        return true if new_repository_file_url?
        false
      end

      private

      def uri
        @uri ||= Addressable::URI.parse(url)
      end

      def parts
        @parts ||= Array(uri.path.split("/")[1..-1])
      end

      def anchor
        @anchor ||= uri.fragment
      end

      def team_url?
        parts[0] == "orgs" && parts[2] == "teams"
      end

      def organization
        @organization ||=
          cache.getset("model_for_url:organization:#{parts[0]}") do
            Organization.find_by_login(parts[0])
          end
      end

      def team_organization
        @organization ||=
          cache.getset("model_for_url:organization:#{parts[1]}") do
            Organization.find_by_login(parts[1])
          end
      end

      def team
        return unless team_organization.present?

        @team ||=
          cache.getset("model_for_url:organization:#{parts[1]}:team:#{parts[3]}") do
            team_organization.teams.find_by_slug(parts[3])
          end
      end

      def user_url?
        parts.length == 1
      end

      def user
        @user ||=
          cache.getset("model_for_url:user:#{parts[0]}") do
            User.find_by_login(parts[0])
          end
      end

      def bot_url?
        parts.length == 1 && parts[0] =~ /.*\[bot\]\z/
      end

      def bot
        @user ||=
          cache.getset("model_for_url:bot:#{parts[0]}") do
            Bot.find_by_login(parts[0])
          end
      end

      def repo_url?
        parts.length == 2
      end

      def repo
        return unless user.present?

        @repo ||=
          cache.getset("model_for_url:owner:#{parts[0]}:repo:#{parts[1]}") do
            user.find_repo_by_name(parts[1])
          end
      end

      def project
        return unless owner = repo || organization

        owner.projects.where(number: parts.last).first
      end

      def comment_thread_or_event_url?
        anchor.present?
      end

      def comment_thread_or_event
        return unless repo.present?

        @comment_or_event ||= begin
          case
          when match = /\Aissuecomment-(\d+)\z/.match(anchor)
            IssueComment.find(T.must(match[1]))
          when match = /\Adiscussioncomment-(\d+)\z/.match(anchor)
            DiscussionComment.find(T.must(match[1]))
          when match = /\Ar(\d+)\z/.match(anchor)
            PullRequestReviewComment.find(T.must(match[1]))
          when match = /\Acommitcomment-(\d+)\z/.match(anchor)
            CommitComment.find(T.must(match[1]))
          when match = /\Aevent-(\d+)\z/.match(anchor)
            IssueEvent.find(T.must(match[1]))
          when match = /\Apullrequestreviewthread-(\d+)\z/.match(anchor)
            PullRequestReviewThread.find(T.must(match[1]))
          end
        end
      end

      def issue_pull_discussion_label_or_milestone_url?
        parts.length > 3 &&
          %w[issues pull discussions labels milestones].include?(parts[2])
      end

      def project_url?
        parts.length >= 3 &&
          parts.last(2)[0] == "projects"
      end

      def issue_pull_discussion_label_or_milestone
        return unless repo.present?

        @issue_pull_discussion_label_or_milestone ||= begin
          case parts[2]
          when "issues"
            repo.issues.find_by_number(parts[3]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          when "pull"
            issue = repo.issues.find_by_number(parts[3]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            issue.pull_request
          when "discussions"
            repo.discussions.find_by_number(parts[3])
          when "labels"
            repo.labels.find_by_name(parts[3])
          when "milestones"
            repo.milestones.find_by_number(parts[3])
          end
        end
      end

      def release_url?
        parts.length == 5 && parts[2] == "releases" && parts[3] == "tag"
      end

      def release
        return unless repo.present?

        repo.releases.find_by_tag_name(parts[4])
      end

      def repository_advisory_url?
        parts[2] == "security" and parts[3] == "advisories"
      end

      def repository_advisory
        @repository_advisory ||= RepositoryAdvisory.find_by(ghsa_id: parts[4])
      end

      def old_user_asset_url?
        parts.length == 5 && parts[2] == "assets"
      end

      def old_user_asset
        return unless repo.present?
        @old_user_asset ||= UserAsset.find_by(guid: parts[4])
        return unless @old_user_asset&.repository == repo
        @old_user_asset
      end

      def new_user_asset_url?
        parts.length == 3 && parts[0] == "user-attachments" && parts[1] == "assets"
      end

      def new_user_asset
        @new_user_asset ||= UserAsset.find_by(guid: parts[2])
      end

      def old_repository_file_url?
        parts.length == 5 && parts[2] == "files"
      end

      def old_repository_file
        return unless repo.present?
        @old_repository_file ||= RepositoryFile.find_by(id: parts[3])
        return unless @old_repository_file&.name&.tap { |n| CGI.escape(n) } == parts[4]
        @old_repository_file
      end

      def new_repository_file_url?
        parts.length == 4 && parts[0] == "user-attachments" && parts[1] == "files"
      end

      def new_repository_file
        @new_repository_file ||= RepositoryFile.find_by(id: parts[2])
        return unless @new_repository_file&.name&.tap { |n| CGI.escape(n) } == parts[3]
        @new_repository_file
      end

      def valid_user_url?
        valid_login? && !reserved_login?
      end

      def reserved_login?
        User.new(login: parts[0]).login_reserved?
      end

      def valid_login?
        !!(parts[0] =~ User::LOGIN_REGEX)
      end

      def scrub_url(url)
        url.gsub(/\d/, "0").gsub(/[a-zA-Z]/, "X")
      end
    end
  end
end
