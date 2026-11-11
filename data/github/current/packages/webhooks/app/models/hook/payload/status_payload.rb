# typed: true
# frozen_string_literal: true

class Hook::Payload::StatusPayload < Hook::Payload
  include Formatter

  delegate :id, :repository, :sha, :target_url, :context, :description, :state, :branches,
    :commit, :created_at, :updated_at, to: :status

  def to_payload_hash
    {
      id: id,
      sha: sha,
      name: repository.name_with_display_owner,
      target_url: target_url,
      avatar_url: Api::Serializer.status_avatar_url(status),
      context: context,
      description: description,
      state: state,
      commit: api_serialize(:git_commit_hash, commit),
      branches: branches_head_refs.map do |branch_head_ref|
        api_serialize(:short_branch_hash, branch_head_ref)
      end,
      created_at: time(created_at),
      updated_at: time(updated_at),
    }
  end

  private

  def status
    hook_event.status
  end

  def branches_head_refs
    branch_refs = branches.first(10).map do |branch_name|
      repository.heads.read(branch_name)
    end

    GitHub::PrefillAssociations.prefill_batch_method(branch_refs, :protected_branch)

    branch_refs
  end

end
