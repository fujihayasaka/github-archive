# typed: true
# frozen_string_literal: true

module Stratocaster
  class EventPayload
    def initialize(attributes)
      @attributes = attributes.with_indifferent_access
    end

    def action
      @attributes[:action].presence
    end

    def actor_id
      actor[:id].presence
    end

    def actor_login
      actor[:login].presence
    end

    def before_sha
      @attributes[:before]
    end

    def comment_commit_id
      id = comment[:commit_id] || @attributes[:commit]
      id.presence
    end

    def comment_id
      id = comment[:id] || @attributes[:comment_id]
      integer_or_nil(id)
    end

    def help_wanted_label_name
      repository[:help_wanted_label_name]
    end

    def commits
      return @commits if defined?(@commits)

      @commits = if @attributes[:commits]
        @attributes[:commits].map(&:with_indifferent_access)
      elsif @attributes[:shas]
        # A list like:
        # ["1a0d2045116af1bcab55dcf63bd8fbd12506d67e", "somebody@example.com",
        #  "Create test-pls.md", "Mr. Rumpelstiltskin", true]
        @attributes[:shas].map do |legacy_array|
          author_hash = HashWithIndifferentAccess.new(email: legacy_array[1],
                                                      name: legacy_array[3])
          HashWithIndifferentAccess.new(sha: legacy_array[0],
                                        message: legacy_array[2],
                                        author: author_hash,
                                        distinct: legacy_array[4])
        end
      end
    end

    def download_id
      integer_or_nil(download[:id])
    end

    def download_name
      download[:name].presence
    end

    def forkee_full_name
      if forkee.is_a?(Hash)
        forkee[:full_name].presence
      end
    end

    def forkee_id
      id = case forkee
      when Hash
        forkee[:id]
      when String
        forkee
      end

      integer_or_nil(id)
    end

    def head_sha
      @attributes[:head]
    end

    def issue_body
      issue[:body].presence
    end

    def issue_comments_count
      comments_count = issue[:comments]
      integer_or_nil(comments_count)
    end

    def issue_title
      if issue && issue.is_a?(Hash)
        issue[:title]
      end
    end

    def issue_id
      id = case issue
      when Hash
        issue[:id]
      when String
        issue
      end

      integer_or_nil(id)
    end

    def issue_number
      number = issue[:number]
      integer_or_nil(number)
    end

    def issue_state
      issue[:state].presence
    end

    def label_color
      label[:color].presence
    end

    def label_name
      label[:name].presence
    end

    def member_id
      integer_or_nil(member[:id])
    end

    def object
      @attributes[:object].presence
    end

    def organization_id
      integer_or_nil(organization[:id])
    end

    def pages
      @attributes.fetch(:pages, {})
    end

    def pull_request_comments_count
      comments_count = pull_request[:comments]
      integer_or_nil(comments_count)
    end

    def pull_request_body
      pull_request[:body].presence
    end

    def pull_request_url
      pull_request[:url]
    end

    def pull_request_id
      integer_or_nil(pull_request[:id])
    end

    def pull_request_title
      pull_request[:title]
    end

    def pull_request_number
      number = pull_request[:number]
      integer_or_nil(number)
    end

    def pull_request_state
      pull_request[:state].presence
    end

    def push_id
      @attributes[:push_id]
    end

    def pusher_type
      @attributes[:pusher_type]
    end

    def ref
      @attributes[:ref].presence
    end

    def ref_type
      @attributes[:ref_type].presence
    end

    def release_assets
      release.fetch(:assets, []).map { |asset| asset.with_indifferent_access }
    end

    def release_id
      integer_or_nil(release[:id])
    end

    def release_name
      release[:name].presence
    end

    def release_tag_name
      release[:tag_name].presence
    end

    def release_short_description_html
      release[:short_description_html].presence&.html_safe # rubocop:disable Rails/OutputSafety
    end

    def release_short_description_html_truncated?
      release[:is_short_description_html_truncated].presence
    end

    def release_mentions
      release[:mentions]
    end

    def target_avatar_url
      if target.is_a?(Hash)
        target[:avatar_url].presence
      end
    end

    def target_bio
      if target.is_a?(Hash)
        target[:bio].presence
      end
    end

    def target_followers_count
      if target.is_a?(Hash)
        integer_or_nil(target[:followers])
      end
    end

    def target_name
      if target.is_a?(Hash)
        target[:name].presence
      end
    end

    def target_id
      if target.is_a?(Hash)
        integer_or_nil(target[:id])
      end
    end

    def target_login
      # We normally use target with indifferent access when it's a Hash, but
      # that causes unnecessary allocations. We can avoid that by checking both
      # string and symbol manually.
      target_attributes = @attributes["target"]

      case target_attributes
      when Hash
        target_attributes[:login].presence || target_attributes["login"].presence
      when String
        target_attributes.presence
      end
    end

    def target_type
      target_attributes = @attributes["target"]
      if target_attributes.is_a?(Hash)
        target_attributes[:type].presence || target_attributes["type"].presence
      end
    end

    def target_public_repos_count
      if target.is_a?(Hash)
        integer_or_nil(target[:public_repos])
      end
    end

    def team_id
      integer_or_nil(team[:id])
    end

    def team_name
      team[:name].presence
    end

    def user_id
      integer_or_nil(user[:id])
    end

    def maintainer_id
      integer_or_nil(@attributes.fetch(:maintainer_id, nil))
    end

    def sponsor_id
      integer_or_nil(@attributes.fetch(:sponsor_id, nil))
    end

    def review_id
      integer_or_nil(@attributes.fetch(:review_id, nil))
    end

    private

    def integer_or_nil(number)
      number.to_i if number.present?
    end

    def actor
      @attributes.fetch(:actor, {}).with_indifferent_access
    end

    def comment
      @attributes.fetch(:comment, {}).with_indifferent_access
    end

    def download
      @attributes.fetch(:download, {}).with_indifferent_access
    end

    def forkee
      if @attributes[:forkee].is_a?(Hash)
        @attributes[:forkee].with_indifferent_access
      else
        @attributes[:forkee]
      end
    end

    def issue
      issue_attributes = @attributes.fetch(:issue, {})

      if issue_attributes.is_a?(Hash)
        issue_attributes.with_indifferent_access
      else
        issue_attributes
      end
    end

    def label
      @attributes.fetch(:label, {}).with_indifferent_access
    end

    def member
      @attributes.fetch(:member, {})
    end

    def organization
      @attributes.fetch(:organization, {}).with_indifferent_access
    end

    def pull_request
      if @attributes.key?(:pull_request)
        @attributes[:pull_request].with_indifferent_access
      else
        issue.fetch(:pull_request, {}).with_indifferent_access
      end
    end

    def release
      @attributes.fetch(:release, {}).with_indifferent_access
    end

    def repository
      repo_attributes = @attributes[:repo] || @attributes[:repository] || {}
      repo_attributes.with_indifferent_access
    end

    def target
      target_attributes = @attributes[:target]

      if target_attributes.is_a?(Hash)
        target_attributes.with_indifferent_access
      else
        target_attributes
      end
    end

    def team
      @attributes.fetch(:team, {}).with_indifferent_access
    end

    def user
      @attributes.fetch(:user, {}).with_indifferent_access
    end
  end
end
