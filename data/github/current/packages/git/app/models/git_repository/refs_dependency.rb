# typed: false
# frozen_string_literal: true

module GitRepository::RefsDependency
  # Write several refs at a time.
  # This is not a very safe function:
  #   - it acts as if all refs were written with :backup => false
  #   - does not run post_receives by default (i.e. no Push records)
  # Arguments:
  #   - updates    - an array like [[refname, before_oid, after_oid], ...]
  #   - no_custom_hooks - skip running pre-receive hooks
  def batch_write_refs(author, updates, reflog: {}, attempts_remaining: 10, clear_ref_cache: true, priority: :high, no_custom_hooks: false, post_receive: false)
    # guard against writing to refs outside of the refs/ namespace
    # like HEAD and root repository files
    updates.each do |refname, _before, _after|
      if !refname.start_with?("refs/")
        fail "Refusing to write ref outside the refs/ namespace: #{refname}"
      end
    end

    raise TypeError, "author must not be nil" if author.nil?

    need_retry = false

    name, email = User.git_author_info(author)
    sockstat = reflog.merge(committer_name: name.b, committer_email: email.b)
    tpc = ::GitHub::DGit.update_refs_coordinator(self, priority: priority)
    reflog = reflog_entry(author).merge(reflog)
    raise Git::Ref::UpdateError.new("reflog data missing fields") unless reflog_data_valid?(reflog)
    updates.each do |qualified_name, old_oid, new_oid|
      check_custom_hooks(old_oid, new_oid, qualified_name, reflog_data: reflog, no_custom_hooks: no_custom_hooks)
    end

    begin
      txn_status = tpc.commit(updates,
                              sockstat,
                              GitHub::JSON.encode(reflog))
      status = txn_status[:err].nil? ? 0 : 1
      stderr = txn_status.inspect

      updates.each do |refname, before, _after|
        if (ref_status = txn_status[:refs_status][refname])
          if ref_status.include?("lock exists")
            need_retry = true
          elsif match = ref_status.match(/reference already exists/)
            raise Git::Ref::ReferenceExistsError, match[0]
          elsif match = ref_status.match(/(#{Regexp.escape(refname)} )?is at [0-9a-f]{40} but expected 0{40}/)
            raise Git::Ref::ReferenceExistsError, match[0]
          elsif match = ref_status.match(/(#{Regexp.escape(refname)} )?is at [0-9a-f]{40} but expected #{before}/)
            raise Git::Ref::ComparisonMismatch, match[0]
          elsif ref_status.include?("unable to resolve reference") &&
                before && before != GitHub::NULL_OID
            raise Git::Ref::ComparisonMismatch, "#{refname} expected to be at #{before}"
          end
        end
      end
    rescue ::GitHub::DGit::ThreepcBusyError
      raise if attempts_remaining <= 1 || priority == :high
      need_retry = true
      # Low priority jobs have a 3PC timeout of 2 seconds. Since they are low
      # priority, they are likely called from Aquaduct jobs and therefore it
      # shouldn't matter if we wait for the result a bit longer.
      sleep(rand(6..12))
    end

    if need_retry && attempts_remaining > 1
      return batch_write_refs(author, updates, reflog: reflog,
                              attempts_remaining: attempts_remaining - 1,
                              clear_ref_cache: clear_ref_cache,
                              priority: priority,
                              no_custom_hooks: no_custom_hooks,
                              post_receive: post_receive)
    end

    if status == 0
      unless clear_ref_cache
        # TODO Make this update all ref caches, not just `#refs`
        updates.each { |refname, _before, after| refs.write_update(refname, after) }
      end
    else
      raise Git::Ref::UpdateFailedSensitive, "git-update-ref #{updates.inspect} failed: #{stderr.inspect}"
    end

    if post_receive
      updates_for_job = updates.map do |refname, before, after|
        Git::Ref::Update.new(repository: self, refname: refname, before_oid: before || GitHub::NULL_OID, after_oid: after)
      end
      RepositoryPushJobTrigger.new(repository, author.is_a?(User) ? author : nil, updates_for_job, txn_status[:committed_at]).enqueue
    end

    if clear_ref_cache
      self.clear_ref_cache
      self.set_ref_cache_key(txn_status[:checksum])
    end

    txn_status[:committed_at]
  end

  private

  # Internal: Build a reflog entry hash for the given user.
  #
  # person - The person responsible for modifying the ref. Can either be a User
  #          object or a hash with :name and :email keys.
  #
  # Returns a Hash with extended reflog information.
  def reflog_entry(person)
    name, email = User.git_author_info(person)
    entry = {
      user_name: name,
      user_email: email,
      server: Socket.gethostname,
      real_ip: GitHub.context[:actor_ip],
      user_agent: GitHub.context[:user_agent],
      repo_name: self.full_name,
      repo_public: self.public?,
      from: GitHub.context[:from],
      via: GitHub.context[:from]
    }

    if person.is_a?(User)
      entry.merge!({ user_id: person.id, user_login: person.login })
    end

    entry
  end

  def reflog_data_valid?(reflog_data)
    reflog_data[:repo_name].present? &&
    (reflog_data[:user_login].present? || reflog_data[:user_name].present?) &&
    [true, false].include?(reflog_data[:repo_public])
  end
end
