# typed: true
# frozen_string_literal: true

module Commits::ReactPayloadDataDependency
  include Commits::AuthorHelper
  include CommitHelper
  include UrlHelper
  include TextHelper
  include AvatarHelper

  class CommitMessageRenderType < T::Enum
    enums do
      Default = new # truncates the subject to 72 characters
      ExtendedSubject = new # truncates the subject to 200 characters
      ExtendedSubjectLinked = new # truncates the subject to 200 characters, wraps the subject in a link
      FullSubject = new # does not truncate the subject
    end
  end

  def build_grouped_commits_payload(commits, current_user, order: :desc, pull_request: nil)
    if Rails.env.development?
      raise unless [:asc, :desc].include?(order)
    end

    source = pull_request ? "pull_request" : "commits"
    commit_count = commits&.count || 0
    GitHub.dogstats.distribution_time("commits.payload.prefill.time", tags: ["source:#{source}", "commit_count:#{commit_count}"]) do
      prefill_core_commit_associations(commits, current_user, message_render_type: CommitMessageRenderType::ExtendedSubjectLinked)
    end

    commits_grouped_by_date = \
      if order == :asc
        grouped_commits(commits, current_user)
      else
        grouped_commits(commits, current_user).reverse
      end

    commits_grouped_by_date.map do |item|
      {
        title: item[0].strftime("%b %-d, %Y"),
        commits: item[1].map! do |commit|

          {
            **build_core_commit_payload(commit, current_user, message_render_type: CommitMessageRenderType::ExtendedSubjectLinked, pull_request: pull_request)
          }
        end
      }
    end
  end

  def grouped_commits(commits, current_user)
    zone = current_user&.time_zone || Time.zone
    return [] if commits.nil?
    commits.group_by do |commit|
      commit.committed_date.in_time_zone(zone).to_date
    end.sort
  end

  def build_deferred_commit_payload(commits, repo, current_user)
    preload_errors = preload_deferred_commit_data(commits, repo)

    commits&.map do |commit|
      if !preload_errors.include?(:commit_signature)
        signed_badge = Commits::SignedCommitBadge.for(commit, current_user: current_user)
        if signed_badge.present?
          is_viewer = signed_badge.signer&.is_viewer?
          signer_avatar_url = signed_badge.signer&.avatar_url
          signer_login = signed_badge.signer&.display_login
          signature_certificate_subject = initialize_certificate_attributes(signed_badge.subject)
          signature_certificate_issuer = initialize_certificate_attributes(signed_badge.issuer)
          signature_type = signed_badge.typename
          key_expired = signed_badge.expired? unless signed_badge.signer.nil?
          key_revoked = signed_badge.revoked? unless signed_badge.signer.nil?
          verified_at = signed_badge.verified_at&.iso8601
        end

        verification_status = commit.verification_status

        signature_information = {
          signatureVerificationReason: commit.signature_verification_reason,
          hasSignature: commit.has_signature?,
          verifiedAt: verified_at,
          isViewer: is_viewer,
          keyExpired: key_expired,
          keyId: commit.signature_issuer_key_id_hex || commit.ssh_key_fingerprint_hex,
          keyRevoked: key_revoked,
          signedByGitHub: commit.signed_by_github?,
          signerAvatarUrl: signer_avatar_url,
          signerLogin: signer_login,
          signatureCertificateSubject: signature_certificate_subject,
          signatureCertificateIssuer: signature_certificate_issuer,
          signatureType: signature_type,
        }
      end

      if on_behalf_of = commit.on_behalf_of
        on_behalf_of_out = {}.tap do |opts|
          opts[:login] = on_behalf_of.display_login
          opts[:displayName] = on_behalf_of.name
          opts[:avatarUrl] = on_behalf_of.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
          opts[:path] = user_path(on_behalf_of)
        end
      end

      if preload_errors.include?(:commit_status_check)
        status_check_status = { state: "error" }
      else
        status_check_status = commit.status_check_rollup.as_json(only: %w[state short_text])
      end

      {
        oid: commit.oid,
        commentCount: commit.comment_count,
        statusCheckStatus: status_check_status,
        verifiedStatus: verification_status,
        signatureInformation: signature_information,
        onBehalfOf: on_behalf_of_out
      }
    end
  end

  sig { params(commit: T.untyped, current_user: T.untyped, message_render_type: CommitMessageRenderType, pull_request: T.untyped, include_pusher: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def build_core_commit_payload(commit, current_user, message_render_type:, pull_request: nil, include_pusher: false)
    commit_link_options = { use_default_font_color: true }

    commit_relative_path = \
      if pull_request
        "#{pull_request_path(pull_request)}/commits/#{commit.oid}"
      else
        commit_path(commit)
      end

    short_message = nil
    short_message_markdown = nil
    short_message_markdown_link = nil
    body_message_html = nil

    case message_render_type
    when CommitMessageRenderType::Default
      short_message = commit.short_message_text
      short_message_markdown_link = commit_short_message_link(commit, commit_relative_path, nil, commit_link_options)
      body_message_html = commit&.message_body_html
    when CommitMessageRenderType::ExtendedSubject
      short_message_markdown = commit_message_markdown(commit.longer_short_message_html)
      body_message_html = commit&.message_body_html_longer_subject
    when CommitMessageRenderType::ExtendedSubjectLinked
      short_message = commit.longer_short_message_text
      short_message_markdown_link = commit_short_message_link(commit, commit_relative_path, commit.longer_short_message_html, commit_link_options)
      body_message_html = commit&.message_body_html_longer_subject
    when CommitMessageRenderType::FullSubject
      short_message_markdown = commit_message_markdown(commit.full_subject_html)
      body_message_html = commit&.full_body_html
    else
      T.absurd(message_render_type)
    end

    {
      oid: commit.oid,
      url: commit_relative_path,
      authoredDate: commit.authored_date,
      committedDate: commit.committed_date,
      shortMessage: short_message,
      shortMessageMarkdown: short_message_markdown,
      shortMessageMarkdownLink: short_message_markdown_link,
      bodyMessageHtml: body_message_html,

      **initialize_commit_authors(commit, current_user, include_pusher:),
    }
  end

  sig { params(commits: T.untyped, current_user: T.untyped, message_render_type: CommitMessageRenderType).void }
  def prefill_core_commit_associations(commits, current_user, message_render_type:)
    return unless commits.present?

    core_promises = []

    case message_render_type
    when CommitMessageRenderType::Default
      core_promises.concat(commits.flat_map do |commit|
        [
          commit.async_message_body_html,
          commit.async_short_message_html,
        ]
      end)
    when CommitMessageRenderType::ExtendedSubject, CommitMessageRenderType::ExtendedSubjectLinked
      core_promises.concat(commits.flat_map do |commit|
        [
          commit.async_longer_short_message_html,
          commit.async_message_body_html_longer_subject,
        ]
      end)
    when CommitMessageRenderType::FullSubject
      core_promises.concat(commits.flat_map do |commit|
        [
          commit.async_full_subject_html,
          commit.async_full_body_html,
        ]
      end)
    else
      T.absurd(message_render_type)
    end

    author_promises = prefill_commit_author_promises(commits, current_user)
    core_promises.concat(author_promises)

    Promise.all(core_promises).sync
  end

  def preload_deferred_commit_data(commits, repo)
    return [] if commits.blank?

    preload_errors = []

    Commit.prefill_comment_counts(commits)
    # Here we have to set the repository on the commit objects so that later calculations use the correct
    # repository context when calculating the status check rollup, as that can vary depending on the repository
    commits.each { |commit| commit.repository = repo }

    begin
      # prevents calling into verify_signature more than once when we hit verification_status on each commit
      Promise.all(commits.map(&:async_signature)).sync

      begin
        Promise.all(commits.map { |commit| [commit.verification_status,  commit.status_check_rollup] }.flatten).sync
      rescue ActiveRecord::ActiveRecordError
        # Still try and preload the verification status
        Promise.all(commits.map(&:verification_status)).sync

        preload_errors << :commit_status_check
      end

      # batch retrieve commit signatures
      Commit.prefill_verified_signature(commits, repo)

      Promise.all(commits.map(&:async_on_behalf_of)).sync
    rescue GitSigning::Error => e
      preload_errors << :commit_signature

      begin
        # Still try to preload status checks
        Promise.all(commits.map(&:status_check_rollup)).sync
      rescue ActiveRecord::ActiveRecordError
        preload_errors << :commit_status_check
      end
    end

    preload_errors
  end

  def initialize_certificate_attributes(certificate_attributes)
    {
      common_name: certificate_attributes.common_name,
      email_address: certificate_attributes.email_address,
      organization: certificate_attributes.organization,
      organization_unit: certificate_attributes.organization_unit
    }
  end
end
