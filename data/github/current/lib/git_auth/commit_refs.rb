# typed: true
# frozen_string_literal: true

require "instrumentation/stats_reporter"

module GitAuth
  class CommitRefs < GitAuth::PushHandler
    include UrlHelpers

    include SecretScanning::Features::FeatureFlagHelper

    PERMISSION_DENIED = "permission denied"
    HOOK_DECLINED = "pre-receive hook declined"

    attr_reader :body

    def initialize(body)
      @body = body
    end

    def git_sockstat
      @git_sockstat ||= GitHub::GitSockstat.parse(body.sockstat)
    end

    def actor
      @actor ||= actor_from_ctx(body.commit_ref_ctx)
    end

    def process
      if !ActiveRecord::Base.single_database_cluster?
        ActiveRecord::Base.connected_to(role: :reading) do
          ActiveRecord::Base.connected_to_many([ApplicationRecord::Repositories, ApplicationRecord::RepositoriesPushes], role: :writing) do
            process_for_real
          end
        end
      else
        process_for_real
      end
    end

    def process_for_real
      trace_phase(refs_size: refs.size) do
        return not_found_payload if target.repository.nil?

        if body.pre_receive_hook_result != "ok"
          log_phase(
            "Returning from commit refs process due to pre-receive hook failure",
            phase: "pre_receive_hook_declined"
          )
          remove_quarantine if spokes_quarantine?
          return hook_declined_payload
        end

        pre_receive_rule_suites = nil
        push_state = nil

        if spokes_quarantine?
          push_state = create_push_state
          repository.spokes_api_context.push_state = push_state

          begin
            pre_receive_rule_suites = trace_phase(phase: "pre_receive_rules", refs_size: refs.size) do
              check_pre_receive_rules
            end

            if pre_receive_rule_suites.present? && refs.any?(&:disallowed?)
              log_phase(
                "Returning from commit refs process due to pre-receive rule failure",
                phase: "pre_receive_rule_failure",
              )
              result = {
                "ok" => true,
                "err" => refs.display_message,
                "refs" => refs.payload,
              }
              remove_quarantine
              return result
            end
          rescue RuleEngine::Errors::RefLimitReached
            refs.each do |ref|
              ref.disallow! "push declined due to ref limit"
            end

            refs.ref_limit_error = true

            result = {
              "ok" => true,
              "err" => refs.display_message,
              "refs" => refs.payload,
            }

            GitHub.dogstats.increment("gitauth.commit_refs.process.ref_limit_reached")

            log_phase(
              "Returning from commit refs process due to ref limit",
              phase: "pre_receive_rule_failure",
            )

            remove_quarantine
            return result
          end

          # Update the push state in context with the value commit_quarantine returns. We don't
          # use it now, but if we do add more Spokes Access API calls after this
          # point, we'll want to include this push state instead of the initial
          # one.
          post_commit_push_state = commit_quarantine(push_state, preserve_quarantine: preserve_quarantine?)
          repository.spokes_api_context.push_state = post_commit_push_state

          # Drop quarantine_id from sockstat in order to avoid unexpected errors
          # from Git.
          git_sockstat.remove("quarantine_id")
        end

        git_sockstat.register(actor)

        ## Update phase
        # Invoke custom update ref hook
        # update ref file system hooks are not supported
        begin
          Instrumentation.track_time("gitauth.commit_refs.process.duration", tags: ["phase:policy_decisions"]) do
            if target.normal_repo?
              trace_phase(phase: "maintainer_ref_access", refs_size: refs.size) do
                check_maintainer_ref_access
              end
            end
            trace_phase(phase: "post_receive_rules", refs_size: ref_update_objects.size) do
              check_post_receive_rules(pre_receive_rule_suites)
            end
          end

          refs_committed_at = nil
          if refs.any?(&:allow?)
            info = trace_phase(phase: "tpc", refs_size: allowed_refs.size) do
              commit_info = tpc.commit(allowed_refs.map(&:payload), git_sockstat.to_h)
              commit_info[:refs_status].each do |refname, message|
                refs[refname].message = message
              end
              commit_info
            end
            # set messages on refs if they didn't get set above
            if info[:err].nil?
              allowed_refs.each(&:ok!)
            else
              allowed_refs.each(&:failed!)
            end
            refs_committed_at = info[:committed_at]
          elsif target.normal_repo?
            log_phase("Nothing to commit", phase: "no_commit")
            # Update the target repository's pushed count in case all ref updates
            # were denied. If no ref updates happened, the post-receive hooks won't
            # fire and no network maintenance will be triggered.
            #
            # By updating the pushed count here, we can in turn trigger repository
            # network maintenance to run.
            target.repository.network.increment_pushed_counts
          end

          result = {
            "ok"   => true,
            "err"  => refs.display_message,
            "refs" => refs.payload,
          }
          result["committed_at"] = refs_committed_at.utc.iso8601(6) if refs_committed_at

          ref_updates = refs.filter do |ref|
            ref.message.start_with?("ok ") && !(ref.before == GitHub::NULL_OID && ref.after == GitHub::NULL_OID)
          end.map do |ref|
            {
              "refname" => ref.decoded_name,
              "before_oid" => ref.before,
              "after_oid" => ref.after,
            }
          end

          pusher = [git_sockstat.value("user_login"), git_sockstat.value("pubkey_verifier_login")].compact.first.to_s

          data = {
            "pusher" => pusher,
            "committed_at" => refs_committed_at,
            "ref_updates" => ref_updates,
            "sockstat" => git_sockstat,
          }
        ensure
          # If there's no information populated in data, we didn't make any ref updates.
          # We should still publish the push event in this case, since we've accepted the push and need to notify the monolith of quarantine.
          data ||= {
            "pusher" => [git_sockstat.value("user_login"), git_sockstat.value("pubkey_verifier_login")].compact.first.to_s,
            "sockstat" => git_sockstat,
            "ref_updates" => [],
          }

          data["pusher_id"] = (git_sockstat.value("user_id") || git_sockstat.value("pubkey_verifier_id")).to_i

          publish_push_event(data, push_state)
        end

        if !ref_updates.empty?
          # Generate the "push notices" to send to the user. We generate them out of the same class as we do for
          # the postrx call transitionally, so we need to generate the same structure as we pass there
          if target.normal_repo?
            notices = PushNotices.call(target.repository, data)
            result["messages"] = notices.for_display if notices.any?
          end
        end

        if GitHub.single_tenant_enterprise?
          # Tell the github_audit topic on the syslog about this push. We fake the
          # program and cmdline keys for continuity with the post-receive hook
          # that used to log.
          audit_kv = @git_sockstat.to_h
          audit_kv.delete("token")
          audit_kv["program"] = "run-hook-post-receive"
          audit_kv["cmdline"] = "/usr/lib/git-core/git-run-hook post-receive ."
          Syslog.open Audit::Syslog::SYSLOG_IDENT, Audit::Syslog::SYSLOG_OPTIONS, Audit::Syslog::SYSLOG_FACILITY unless Syslog.opened?
          Syslog.log Syslog::LOG_INFO, "%s", JSON.generate(audit_kv)
        end

        result
      end

    end

    private

    def publish_push_event(data, push_state)
      GitHub.dogstats.distribution_time("commit_refs.publish_push_event") do
        sockstat_keys = %w(
          oauth_access_id
          user_programmatic_access_id
          installation_id
          installation_type
        )

        ref_updates = data["ref_updates"].map do |ref_update|
          ::Git::Ref::Update.new(repository: repository, refname: ref_update["refname"],
                                 before_oid: ref_update["before_oid"], after_oid: ref_update["after_oid"])
        end

        sockstat_context = {}

        unless data["sockstat"].nil?
          sockstat_context = data["sockstat"].data.slice(*sockstat_keys)

          sockstat_context.transform_keys!(&:to_sym)
        end

        RepositoryPushJobTrigger.new(
          repository,
          data["pusher"],
          ref_updates,
          data["committed_at"],
          data["push_options"],
          sockstat_context,
          quarantine_push_state: (push_state.present? && preserve_quarantine?) ? Base64.encode64(push_state.to_s) : nil,
          pusher_id: data["pusher_id"],
        ).enqueue
      end
    end

    # We'll only keep quarantine around and clear it async for normal repos.
    # Wikis and gists will have quarantine cleared when it is committed.
    def preserve_quarantine?
      target.normal_repo?
    end

    def not_found_payload
      {
        "ok"     => false,
        "err"    => "Repository not found.",
        "refs"   => {},
        "reason" => "repo-not-found",
      }
    end

    def too_many_updates_payload(max_ref_updates)
      {
        "ok"     => false,
        "err"    => "Repository policies do not allow pushes that update more than #{max_ref_updates} #{"branch".pluralize(max_ref_updates)} or #{"tag".pluralize(max_ref_updates)}.",
        "refs"   => {},
        "reason" => "too-many-updates",
      }
    end

    def hook_declined_payload
      {
        "ok"   => true, # babeld ignores per-ref failures when "ok" is false
        "err"  => "",
        "refs" => Hash[refs.map { |ref| [ref.encoded_name, HOOK_DECLINED] }],
      }
    end

    def check_maintainer_ref_access
      refs.each do |ref|
        if git_sockstat.value("maintainer") && actor
          # The pushable_by? query is pretty expensive, and
          # we are running it within a loop.
          # We could consider flattening the query.
          # However, this is the case where a maintainer is
          # pushing to a PR, so we do not expect them to push
          # more than one ref, so it seems fine.
          pushable_by = target.repository.pushable_by?(actor, ref: ref.decoded_name)

          if !pushable_by
            ref.disallow! PERMISSION_DENIED
            next
          elsif ref.after == GitHub::NULL_OID
            # maintainers can't delete the contributor's branch
            ref.disallow! PERMISSION_DENIED
            next
          end
        end
      end
    end

    def ref_update_objects
      refs.select(&:undecided?).map do |ref|
        Git::Ref::Update.new(
          repository: target.repository,
          refname: ref.decoded_name,
          before_oid: ref.before,
          after_oid: ref.after,
          fast_forward: if ref.status == "ff"
                          true
                        else
                          (ref.status == "nf" ? false : nil)
                        end,
          wiki: target.wiki?
        )
      end
    end

    def allowed_refs
      refs.select(&:allow?)
    end

    def check_pre_receive_rules
      return nil if actor == :slumlord
      return nil unless target.normal_repo?

      repository = target.repository
      rule_suites = RuleEngine::Evaluator.evaluate_rules(
        repository,
        ref_update_objects,
        actor,
        phase: RuleEngine::Types::Phase::PreReceive,
        options: {
          commit_refs_evaluation: true,
        }
      )

      rule_suites.each do |rule_suite|
        ref_update = T.must(rule_suite.ref_update)

        next if rule_suite.action_permitted?

        ref = refs[ref_update.refname]
        ref.disallow! "push declined due to repository rule violations"

        view_rulesets_url = view_repository_rulesets_url(repository.owner, repository, host: GitHub.urls.host_name, protocol: GitHub.scheme, ref: ref_update.refname)

        message = "error: GH013: Repository rule violations found for #{ref_update.refname}."
        if rule_suite.contains_ruleset_backed_rule_run?
          # Only display the rulesets URL if the rule suite contains at least 1 ruleset-backed rule run.
          message += "\nReview all repository rules at #{view_rulesets_url}\n"
        else
          message += "\n"
        end
        failure_messages = rule_suite.failure_messages(from_cli: true, exclude_violations: false, include_bypassed: true, indicate_bypassed: true)

        if failure_messages.any?
          message += "\n- GITHUB PUSH PROTECTION\n"
          message += "  —————————————————————————————————————————\n"
          message += "    Resolve the following violations before pushing again\n\n"
          failure_messages.each do |failure_message|
            failure_message.each_line do |line|
              message += "    #{line}"
            end
            message += "\n\n"
          end
        end

        if rule_suite.additional_cli_message
          T.must(rule_suite.additional_cli_message).each_line do |line|
            message += "    #{line}"
          end
          message += "\n\n"
        end

        ref.display_message = message
      end

      rule_suites
    end

    def check_post_receive_rules(pre_receive_rule_suites)
      decisions = RefUpdatesPolicy.check(
        repository,
        ref_update_objects,
        actor,
        atomic: body.capabilities[:atomic],
        normal_repo: target.normal_repo?,
        sockstat: git_sockstat,
        pre_receive_rule_suites:,
      )

      decisions.each do |decision|
        ref = refs[decision.ref_update.refname]

        ref.display_message = decision.long_message if decision.long_message
        if decision.allowed?
          # This is the last rule in the chain. This is safe because there are no rules after this
          ref.allow_and_ignore_all_other_rules!
        else
          ref.disallow! decision.short_message
        end
      end
    end

    def target
      @target ||= GitAuth::Target.new(body.path)
    end

    def refs
      @refs ||= GitAuth::Refs.new(body.refs)
    end

    def tpc
      GitHub::DGit.update_refs_coordinator(repository)
    end

    def repository
      target.wiki? ? target.repository.unsullied_wiki : target.repository
    end

    def spokes_quarantine?
      git_sockstat.value("spokes_quarantine")
    end

    def create_push_state
      # Use 'repository' because it is the correct type for wikis (in addition
      # to repositories or gists).
      repository.spokes_api.set_up_push_state \
        quarantine_id: git_sockstat.value("quarantine_id"),
        host_status: body.host_status
    end

    def commit_quarantine(push_state, preserve_quarantine: false)
      trace_phase(phase: "commit_quarantine") do
        # Use 'repository' because it is the correct type for wikis (in addition
        # to repositories or gists).
        repository.spokes_api.commit_quarantine(push_state: push_state, preserve_quarantine: preserve_quarantine)
      end
    end

    def remove_quarantine
      trace_phase(phase: "remove_quarantine") do
        # Use 'repository' because it is the correct type for wikis (in addition
        # to repositories or gists).
        repository.spokes_api.remove_quarantine \
          quarantine_id: git_sockstat.value("quarantine_id")
      end
    end

    sig do
      type_parameters(:R)
      .params(
        phase: T.nilable(String),
        refs_size: T.nilable(Integer),
        block: T.proc.returns(T.type_parameter(:R))
      )
      .returns(T.type_parameter(:R))
    end
    def trace_phase(phase: nil, refs_size: nil, &block)
      tags = []
      attributes = {}
      resource = "gitauth.commit_refs.process"
      attribute_name = "gitauth.commit_refs.process.refs_size"
      duration_metric = "gitauth.commit_refs.process.duration"
      if phase.present?
        tags << "phase:#{phase}"
        attribute_name = "gitauth.commit_refs.process.phase.refs_size"
        resource = "gitauth.commit_refs.process.#{phase}"
        duration_metric = "gitauth.commit_refs.process.phase.duration"
      end
      attributes[attribute_name] = refs_size if refs_size.present?
      Instrumentation.track_time(duration_metric, tags:) do
        GitHub.tracer.in_span(resource, kind: :internal, attributes:) do
          log_phase(phase:, refs_size:) do
            yield
          end
        end
      end
    end

    sig do
      type_parameters(:R)
      .params(
        message: T.nilable(String),
        phase: T.nilable(String),
        refs_size: T.nilable(Integer),
        block: T.nilable(T.proc.returns(T.type_parameter(:R))))
      .returns(T.nilable(T.type_parameter(:R)))
    end
    def log_phase(message = nil, phase:, refs_size: nil, &block)
      log_data = {
        # may be nil if no phase is provided (when we start processing)
        "gh.gitauth.commit_refs.process.phase" => phase
      }
      refs_to_evaluate_field = "gh.gitauth.commit_refs.process.refs_to_evaluate"
      if refs_size.present?
        metric = phase.present? ? "gitauth.commit_refs.process.phase.refs_size" : "gitauth.commit_refs.process.refs_size"
        tags = phase.present? ? ["phase:#{phase}"] : []
        GitHub.dogstats.distribution(metric, refs_size, tags: tags)
        log_data.merge!(refs_to_evaluate_field => refs_size)
      end

      # We only log the status when the block is given
      # since if there is no block, we only log once
      status_field = phase.present? ? "gh.gitauth.commit_refs.process.phase.status" : "gh.gitauth.commit_refs.process.status"
      log_data[status_field] = "started" if block_given?

      log(message || "Started #{phase}", log_data)

      return unless block_given?

      result = yield

      # Don't log refs in phase since this may have change during the evaluation
      log_data.delete(refs_to_evaluate_field)
      log_data[status_field] = "completed"
      log(message || "Completed #{phase}", log_data)

      result
    end

    # Log data
    sig { params(msg: String, data: T::Hash[String, T.untyped]).void }
    def log(msg, data = {})
      data = {
        "code.namespace" => self.class.name,
        "gh.repo.id" => target.repository&.id,
        "gh.repo.path" => target.path,
        "gh.repo.type" => target.type,
        "gh.actor.id" => actor.try(:id) || actor.try(:to_s),
        "gh.actor.type" => actor&.class&.name,
        "gh.gitauth.commit_refs.process.refs_size" => refs.size,
        "gh.request_id" => git_sockstat.value("request_id"),
      }.merge(data)

      GitHub.logger.info(msg.strip, data)
    end
  end
end
