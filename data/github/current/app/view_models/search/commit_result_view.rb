# typed: true
# frozen_string_literal: true

module Search
  class CommitResultView
    include EscapeHelper
    include TextHelper
    include StatusHelper
    include UrlHelper
    include AvatarHelper

    # Create a new CommitResultView from a `page` document hash returned from
    # the Elasticsearch index.
    #
    # hash - Document Hash returned by Elasticsearch
    #

    attr_reader :hash, :author_date
    attr_accessor :repository, :sha, :verification_status, :status_check_rollup,
     :signature_verification_reason, :is_viewer, :key_expired, :key_id, :key_revoked, :signed_by_github,
     :signer_avatar_url, :signer_login, :has_signature, :signature_certificate_subject, :signature_certificate_issuer,
     :signature_type, :hl_subject, :issue_references

    def initialize(hash)
      source                = hash["_source"]
      @id                   = hash["_id"]
      @sha                  = source["hash"]
      @author_date          = source["author_date"]
      @repository           = hash["_model"]
      @name                 = source["name"]
      @message              = source["message"]
      @highlights           = hash["highlight"]
      @verification_status  = :unsigned
      @status_check_rollup  = nil
      @has_signature        = false
      @help_url             = GitHub.help_url
      @hl_subject           = nil
    end

    def user_for_frontend_rendering(user)
      {
        login: user[:login],
        display_name: user[:display_name],
        avatar_url: user[:avatar_url],
      }
    end

    # This method converts the object into a hash containing only fields allowlisted for
    # sending directly to the frontend as JSON
    def for_frontend_rendering
      {
        id: @id,
        sha: @sha,
        author_date: @author_date,
        hl_subject: @hl_subject,
        hl_body: @hl_body,
        message: @message,
        repository: ::Search::ResultsView::repository_for_frontend_rendering(@repository),
        verification_status: @verification_status,
        status_check_rollup: @status_check_rollup,
        help_url: @help_url,
        has_signature: @has_signature,
        is_viewer: @is_viewer,
        key_expired: @key_expired,
        key_id: @key_id,
        key_revoked: @key_revoked,
        signed_by_github: @signed_by_github,
        signer_login: @signer_login,
        signer_avatar_url: @signer_avatar,
        signature_type: @signature_type,
        signature_certificate_subject: @signature_certificate_subject,
        signature_certificate_issuer: @signature_certificate_issuer,
        signature_verification_reason: @signature_verification_reason,
        checks_status_summary: @checks_status_summary,
        checks_header_state: @checks_header_state,
        check_runs: @check_runs,
        committer_attribution: @committer_attribution,
        authors: @authors.map { |author| user_for_frontend_rendering(author) },
        committer: user_for_frontend_rendering(@committer),
        commit_author_tooltip: @commit_author_tooltip,
        issue_references: @issue_references
      }
    end

    # Initialize data for a signed commit using the additional given commit
    # data and signed commit badge data not returned from the initial search
    #
    def initialize_signature(commit, signed_commit_badge)
      @signature_verification_reason = commit.signature_verification_reason
      @key_id = commit.signature_issuer_key_id_hex || commit.ssh_key_fingerprint_hex
      @signed_by_github = commit.signed_by_github?
      if signed_commit_badge.present?
        @is_viewer = signed_commit_badge.signer&.is_viewer?
        @signer_avatar_url = signed_commit_badge.signer&.avatar_url
        @signer_login = signed_commit_badge.signer&.display_login
        @signature_certificate_subject = initialize_certificate_attributes(signed_commit_badge.subject)
        @signature_certificate_issuer = initialize_certificate_attributes(signed_commit_badge.issuer)
        @signature_type = signed_commit_badge.typename
        @key_expired = signed_commit_badge.expired? unless signed_commit_badge.signer.nil?
        @key_revoked = signed_commit_badge.revoked? unless signed_commit_badge.signer.nil?
      end
    end

    def initialize_certificate_attributes(certificate_attributes)
      {
        common_name: certificate_attributes.common_name,
        email_address: certificate_attributes.email_address,
        organization: certificate_attributes.organization,
        organization_unit: certificate_attributes.organization_unit
      }
    end

    # Return the commit title and description. The description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped description String.
    def hl_message(commit, current_user)
      return @hl_message if defined? @hl_message

      @hl_message =
          if highlights? && @highlights.key?("message")
            Commits::CommitMessageHTML.new(@highlights["message"].first, {}, GitHub::Goomba::HighlightedSearchResultPipeline)
          else
            Commits::CommitMessageHTML.new(@message, {})
          end
      @hl_body = truncate_html(@hl_message.body, 140)
      @hl_subject = @hl_message.subject
      issue_refs = commit.issue_references.select { |issue_ref| issue_ref.issue.readable_by?(current_user) }
      @issue_references = issue_refs.map { |issue| issue_refs_for_frontend(issue) }
    end

    def issue_refs_for_frontend(issue_ref)
      issue = issue_ref.belonging
      pull_request = issue.pull_request
      {}.tap do |opts|
        opts[:id]               = issue.number
        opts[:title]            = issue.title
        opts[:state]            = issue.state
        opts[:is_pull_request]  = issue_ref.pull_request?
        opts[:permalink]        = issue.permalink
        opts[:mergable_state]   = pull_request ? pull_request.reviewable_state : nil
        opts[:merged]           = pull_request ? pull_request.merged? : false
      end
    end

    # Returns true if there are highlight fragments for this commit. The
    # highlight fragments contain text from the various repository fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    def initialize_checks_status(view)
      combined_status = view.sorted_statuses
      @checks_status_summary = view.checks_status_summary
      @check_runs = []
      if view.all_succeeded?
        @checks_header_state = "SUCCEEDED"
      elsif view.all_failing?
        @checks_header_state = "FAILED"
      elsif view.pending?
        @checks_header_state = "PENDING"
      else
        @checks_header_state = "UNSUCCESSFUL"
      end

      combined_status.each do |status|
        if status.application
          avatar_url = status.application.url
          avatar_description = "#{status.application.name} (@#{status.application.user.display_login}) generated this status."
          avatar_logo = status.application.preferred_avatar_url
          avatar_background_color = "##{status.application.preferred_bgcolor}"
        elsif status.creator
          avatar_url = user_path(status.creator)
          avatar_description = "@#{status.creator.display_login.chomp('[bot]')} generated this status."
          avatar_logo = avatar_url_for status.creator
          avatar_background_color = "#ffffff"
        end

        check_run = {}.tap do |opts|
          opts[:state]              = status.state
          opts[:description]        = status.description || default_status_check_description(status.state)
          opts[:target_url]         = status.target_url
          opts[:name]               = status.contextual_name
          opts[:icon]               = icon_symbol_for_state(status.state)
          opts[:avatar_url]         = avatar_url
          opts[:avatar_description] = avatar_description
          opts[:avatar_logo]        = avatar_logo
          opts[:avatar_background_color] = avatar_background_color
          opts[:additional_context] = additional_status_check_context(status.state, status.duration_in_seconds)
          opts[:pending]            = status_check_pending?(status.state)
        end

        @check_runs << check_run
      end
    end

    def initialize_commit_authors(commit, current_user)
      committer_attribution(commit)
      authors = commit.async_unique_visible_author_actors(current_user).sync
      @authors = []

      authors.each do |author|
        author_actor = {}.tap do |opts|
          opts[:login]              = author.async_visible_user(current_user).sync&.display_login
          opts[:display_name]       = author.display_name
          opts[:avatar_url]         = author.async_actor.sync&.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
        end
        @authors << author_actor
      end

      authors << commit.committer_actor if @committer_attribution
      @author_names = authors.map { |author| author.async_visible_user(current_user).sync&.display_login || author.display_name }
      @commit_author_tooltip = html_safe_to_sentence(@author_names)
      @commit_author_tooltip += " (non-author committer)" if @committer_attribution

      committer = commit.committer_actor
      if committer != nil
        @committer = {}.tap do |opts|
          opts[:login]              = committer.async_visible_user(current_user).sync&.display_login
          opts[:display_name]       = committer.display_name
          opts[:avatar_url]         = committer.async_actor.sync&.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
        end
      end
    end

    def committer_attribution(commit)
      return @committer_attribution if defined? (@committer_attribution)
      @committer_attribution = !commit.async_authored_by_committer?.sync && !commit.committed_via_web?
    end
  end  # CommitResultView
end  # Search
