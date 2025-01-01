# typed: true
# frozen_string_literal: true

class AuthenticCommitsJob < Repositories::PushApplicationJob

  queue_as :authentic_commits

  sig do
    params(
      repository_id: Integer,
      push_id: Integer,
      commit_shas: T.nilable(T::Array[String]),
      start_sha: T.nilable(String),
      end_sha: T.nilable(String)
    )
    .void
  end
  def perform(repository_id:, push_id:, commit_shas: nil, start_sha: nil, end_sha: nil)
    validate_arguments(commit_shas, start_sha, end_sha)

    if commit_shas&.any?
      has_next_page = T.let(true, T::Boolean)
      next_cursor = T.let(nil, T.untyped)

      until !has_next_page
        commits_response = repository.spokes_api.with_read_after_write(true) do
          repository.spokes_api.list_commits_for_ids(oids: commit_shas, cursor: next_cursor)
        end
        has_next_page = commits_response.next_cursor.present?
        next_cursor = commits_response.next_cursor

        results = verify_and_save_commit_signatures(commits_response.commits.to_a)
        report_signature_stats(results, commits_response.commits.to_a)
      end
    end

    if start_sha.present? && end_sha.present?
      has_next_page = T.let(true, T::Boolean)
      next_cursor = T.let(nil, T.untyped)

      until !has_next_page
        commits_response = repository.spokes_api.with_read_after_write(true) do
          repository.spokes_api.list_commits_for_revisions(revisions: ["#{@tart_sha}..#{end_sha}"], cursor: next_cursor)
        end
        has_next_page = commits_response.next_cursor.present?
        next_cursor = commits_response.next_cursor

        results = verify_and_save_commit_signatures(commits_response.commits.to_a)
        report_signature_stats(results, commits_response.commits.to_a)
      end
    end
  end

  private

  def validate_arguments(commit_shas, start_sha, end_sha)
    raise ArgumentError, "commit_shas, start_sha, and end_sha cannot all be empty" unless commit_shas.present? || start_sha.present? || end_sha.present?
    raise ArgumentError, "commit_shas and (start_sha/end_sha) cannot both be provided" if commit_shas.present? && (start_sha.present? || end_sha.present?)
    raise ArgumentError, "end_sha must be provided if start_sha is provided" if start_sha.present? && !end_sha.present?
    raise ArgumentError, "start_sha must be provided if end_sha is provided" if !start_sha.present? && end_sha.present?
  end

  VerificationResult = T.type_alias do
    {
      message: String,
      signature: String,
      email: String,
      id: String,
      network_id: Integer,
      class: T.untyped,
      user: Users::IUser,
      key_id: String,
      reason: String,
      valid: T::Boolean,
      verified_at: T.nilable(Time),
    }
  end

  sig { params(commits: T::Array[GitHub::Spokes::Proto::Commits::V1::CommitItem]).returns(T::Array[VerificationResult]) }
  def verify_and_save_commit_signatures(commits)
    verification_requests = commits.map do |commit|
      message, signature, email, id = [commit.commit_content&.message, commit.commit_content&.gpg_signature, commit.commit_content&.committer&.email, commit.oid&.id]

      next unless message.present? && signature.present? && email.present? && id.present?
      {
        message: message,
        signature: signature,
        email: email,
        id: id,
        network_id: repository.network_id
      }
    end.compact

    GitSigning.verify_signatures(verification_requests, save_to_db: true)
  end

  sig  do
    params(
      verification_results: T::Array[VerificationResult],
      commits: T::Array[GitHub::Spokes::Proto::Commits::V1::CommitItem]
    ).void
  end
  def report_signature_stats(verification_results, commits)
    signed_by_github = 0
    smime = 0
    gpg = 0
    ssh = 0
    verification_results.each do |result|
      signed_by_github += 1 if result[:email] == GitHub.web_committer_email
      smime += 1 if result[:class] == GitSigning::SMIME
      gpg += 1 if result[:class] == GitSigning::GPG
      ssh += 1 if result[:class] == GitSigning::SSH
    end

    non_github_gpg = gpg - signed_by_github

    unsigned_commits = commits.count - (gpg + smime + ssh)

    GitHub.dogstats.count("authentic_commits_job.commits.count", signed_by_github, tags: ["signed_by_github:true", "type:gpg"]) if signed_by_github > 0
    GitHub.dogstats.count("authentic_commits_job.commits.count", smime, tags: ["signed_by_github:false", "type:smime"]) if smime > 0
    GitHub.dogstats.count("authentic_commits_job.commits.count", non_github_gpg, tags: ["signed_by_github:false", "type:gpg"]) if non_github_gpg > 0
    GitHub.dogstats.count("authentic_commits_job.commits.count", ssh, tags: ["signed_by_github:false", "type:ssh"]) if ssh > 0
    GitHub.dogstats.count("authentic_commits_job.commits.count", unsigned_commits, tags: ["type:unsigned"]) if unsigned_commits > 0
  end

  protected

  sig { override.returns(Integer) }
  def push_id
    get_named_job_argument(:push_id)
  end

  sig { override.returns(Integer) }
  def repository_id
    get_named_job_argument(:repository_id)
  end
end
