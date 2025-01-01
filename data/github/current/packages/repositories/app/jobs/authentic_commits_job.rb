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

        process_cursor_commits(push_id, commits_response)
      end
    end

    if start_sha.present? && end_sha.present?
      has_next_page = T.let(true, T::Boolean)
      next_cursor = T.let(nil, T.untyped)

      until !has_next_page
        commits_response = repository.spokes_api.with_read_after_write(true) do
          repository.spokes_api.list_commits_for_revisions(revisions: ["#{start_sha}..#{end_sha}"], cursor: next_cursor)
        end
        has_next_page = commits_response.next_cursor.present?
        next_cursor = commits_response.next_cursor

        process_cursor_commits(push_id, commits_response)
      end
    end
  end

  private

  sig do
    params(
      push_id: Integer,
      cursor_commits: GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse
    ).void
  end
  def process_cursor_commits(push_id, cursor_commits)
    spokes_commits = cursor_commits.commits.to_a
    unchecked_commits, verification_results = verify_and_save_commit_signatures(push_id, spokes_commits)
    report_signature_stats(verification_results, spokes_commits)
    save_unverified_commits(push_id, unchecked_commits, verification_results) if repository.feature_flag_enabled_or_raise?(:save_unsigned_authentic_commits) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig do
    params(
      push_id: Integer,
      unchecked_commits: T::Array[Commit],
      verification_results: T::Array[VerificationResult]
    ).void
  end
  def save_unverified_commits(push_id, unchecked_commits, verification_results)

    # Save commits for which no signature verification was attempted and those for which the verification failed.
    unverified_commit_oids = unchecked_commits.map { |c| c.oid } + verification_results.filter_map { |r| r[:id] if r[:valid] != true }

    # Filter out commits whose oids exist in the network's family.
    dupe_check_start_time = GitHub::Dogstats.monotonic_time
    existing_family_commits = AuthenticCommit.where(oid: unverified_commit_oids, network_id: repository.network&.family_ids).pluck(:oid)
    lookup_hash = Hash[(existing_family_commits.map { |oid| [oid, nil] })]
    to_upsert = unverified_commit_oids.filter_map do |oid|
      { network_id: repository.network_id,
        oid: oid,
        push_id: push_id,
        verified_at: nil
      } unless lookup_hash.key?(oid)
    end
    dogstats_distribution("authentic_commits.save_unverified_commits.dupe_check_duration", GitHub::Dogstats.duration(dupe_check_start_time))

    insert_start_time = GitHub::Dogstats.monotonic_time
    ActiveRecord::Base.connected_to(role: :writing) { AuthenticCommit.bulk_upsert(to_upsert) }
    dogstats_distribution("authentic_commits.save_unverified_commits.insert_duration", GitHub::Dogstats.duration(insert_start_time))
    dogstats_count("authentic_commits.save_unverified_commits.inserted_count", to_upsert.size)
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

  sig do
    params(
      push_id: Integer,
      spokes_commits: T::Array[GitHub::Spokes::Proto::Commits::V1::CommitItem]
    ).returns([
      T::Array[Commit], # unchecked_commits
      T::Array[VerificationResult]
    ])
  end
  def verify_and_save_commit_signatures(push_id, spokes_commits)
    commits = repository.commits.find(spokes_commits.map { |sc| sc.oid&.id })
    Commit.prefill_signing_data(commits) # batch load signature data

    checked, unchecked = commits.partition do |commit|
      message, signature, email, id = [commit.signing_payload, commit.signature, commit.committer_email, commit.oid]
      message.present? && signature.present? && email.present? && id.present?
    end
    verification_requests = checked.map do |commit|
      message, signature, email, id = [commit.signing_payload, commit.signature, commit.committer_email, commit.oid]
      {
        message: message,
        signature: signature,
        email: email,
        id: id,
        network_id: repository.network_id
      }
    end.compact

    results = GitSigning.verify_signatures(verification_requests, push_id:, save_to_db: true)
    [unchecked, results]
  end

  sig  do
    params(
      verification_results: T::Array[VerificationResult],
      spokes_commits: T::Array[GitHub::Spokes::Proto::Commits::V1::CommitItem]
    ).void
  end
  def report_signature_stats(verification_results, spokes_commits)
    signed_by_github = 0
    signed_by_github_failed = 0
    smime = 0
    smime_failed = 0
    non_github_gpg = 0
    non_github_gpg_failed = 0
    ssh = 0
    ssh_failed = 0

    verification_results.each do |result|
      if result[:email] == GitHub.web_committer_email
        if result[:valid]
          signed_by_github += 1
        else
          signed_by_github_failed += 1
        end
      elsif result[:class] == GitSigning::GPG
        if result[:valid]
          non_github_gpg += 1
        else
          non_github_gpg_failed += 1
        end
      end

      if result[:class] == GitSigning::SMIME
        if result[:valid]
          smime += 1
        else
          smime_failed += 1
        end
      end

      if result[:class] == GitSigning::SSH
        if result[:valid]
          ssh += 1
        else
          ssh_failed += 1
        end
      end
    end

    unsigned_commits = spokes_commits.count - verification_results.count

    dogstats_count("authentic_commits_job.commits.count", signed_by_github, tags: ["signed_by_github:true", "type:gpg", "success:true"]) if signed_by_github > 0
    dogstats_count("authentic_commits_job.commits.count", signed_by_github_failed, tags: ["signed_by_github:true", "type:gpg", "success:false"]) if signed_by_github_failed > 0

    dogstats_count("authentic_commits_job.commits.count", non_github_gpg, tags: ["signed_by_github:false", "type:gpg", "success:true"]) if non_github_gpg > 0
    dogstats_count("authentic_commits_job.commits.count", non_github_gpg_failed, tags: ["signed_by_github:false", "type:gpg", "success:false"]) if non_github_gpg_failed > 0

    dogstats_count("authentic_commits_job.commits.count", smime, tags: ["signed_by_github:false", "type:smime", "success:true"]) if smime > 0
    dogstats_count("authentic_commits_job.commits.count", smime_failed, tags: ["signed_by_github:false", "type:smime", "success:false"]) if smime_failed > 0

    dogstats_count("authentic_commits_job.commits.count", ssh, tags: ["signed_by_github:false", "type:ssh", "success:true"]) if ssh > 0
    dogstats_count("authentic_commits_job.commits.count", ssh_failed, tags: ["signed_by_github:false", "type:ssh", "success:false"]) if ssh_failed > 0

    dogstats_count("authentic_commits_job.commits.count", unsigned_commits, tags: ["type:unsigned"]) if unsigned_commits > 0
  end

  def validate_arguments(commit_shas, start_sha, end_sha)
    raise ArgumentError, "commit_shas, start_sha, and end_sha cannot all be empty" unless commit_shas.present? || start_sha.present? || end_sha.present?
    raise ArgumentError, "commit_shas and (start_sha/end_sha) cannot both be provided" if commit_shas.present? && (start_sha.present? || end_sha.present?)
    raise ArgumentError, "end_sha must be provided if start_sha is provided" if start_sha.present? && !end_sha.present?
    raise ArgumentError, "start_sha must be provided if end_sha is provided" if !start_sha.present? && end_sha.present?
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
