# typed: true
# frozen_string_literal: true

module Api::App::JobEnqueueHelpers
  SOCKSTAT_KEYS = %w(
    oauth_access_id
    user_programmatic_access_id
    installation_id
    installation_type
    self_enqueue_post_receive
  )

  # Internal: Enqueues push job after user pushes data
  #
  # repo - The repository for which to enqueue a job
  # data -  Hash of data with pusher, refupdates and protocol information to enqueue job
  #
  def enqueue_push_job(repo, data)
    ref_updates = data["ref_updates"].map do |ref_update|
      ::Git::Ref::Update.new(repository: repo, refname: ref_update["refname"],
                             before_oid: ref_update["before_oid"], after_oid: ref_update["after_oid"])
    end

    sockstat_context = {}

    unless data["sockstat"].nil?
      parse_data = GitHub::GitSockstat.parse(data["sockstat"])
      sockstat_context = parse_data.data.slice(*SOCKSTAT_KEYS)

      sockstat_context.transform_keys!(&:to_sym)
    end

    return if sockstat_context[:self_enqueue_post_receive]

    RepositoryPushJobTrigger.new(repo, data["pusher"], ref_updates, data["committed_at"], data["push_options"], sockstat_context).enqueue
  end

end
