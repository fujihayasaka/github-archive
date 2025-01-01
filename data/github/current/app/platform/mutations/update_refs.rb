# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateRefs < Platform::Mutations::Base
      include Helpers::GitRefs

      description <<~MD
        Creates, updates and/or deletes multiple refs in a repository.

        This mutation takes a list of `RefUpdate`s and performs these updates
        on the repository. All updates are performed atomically, meaning that
        if one of them is rejected, no other ref will be modified.

        `RefUpdate.beforeOid` specifies that the given reference needs to point
        to the given value before performing any updates. A value of
        `0000000000000000000000000000000000000000` can be used to verify that
        the references should not exist.

        `RefUpdate.afterOid` specifies the value that the given reference
        will point to after performing all updates. A value of
        `0000000000000000000000000000000000000000` can be used to delete a
        reference.

        If `RefUpdate.force` is set to `true`, a non-fast-forward updates
        for the given reference will be allowed.
      MD
      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :ref_updates, [Platform::Inputs::RefUpdate], "A list of ref updates.", required: true

      def self.async_api_can_modify?(permission, repository:, ref_updates:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:update_refs_v2,
            repo: repository,
            current_org: org,
            ref_updates: ref_updates,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, ref_updates:)
        assert_repo_is_writable(repository)

        if ref_updates.empty?
          raise Errors::Unprocessable.new("At least one ref update needs to be specified")
        end

        counts_by_ref = ref_updates.each_with_object(Hash.new(0)) do |ref_update, memo|
          memo[ref_update[:name]] += 1
        end

        duplicated_updates = counts_by_ref.select { |_refname, count| count > 1 }
        if duplicated_updates.any?
          # TODO: Better error message?
          raise Errors::Unprocessable.new("Only one update per ref allowed: #{duplicated_updates.map(&:first).join(", ")}")
        end

        ref_updates_with_invalid_refnames = ref_updates.select do |ref_update|
          GitRPC::Backend::HIDDEN_REFS_FILTER.match?(ref_update[:name]) ||
          GitHub::SHA_LIKE_REF_NAME.match?(ref_update[:name]) ||
          (ref_update[:name].length > GitHub::MAX_REF_LENGTH) ||
          (GitHub::REFS_PREFIX_REF_NAME.match?(ref_update[:name]) && (ref_update[:after_oid] != GitHub::NULL_OID))
        end

        if ref_updates_with_invalid_refnames.any?
          # TODO: Better error message?
          raise Errors::Unprocessable.new("Can not update references: #{ref_updates_with_invalid_refnames.map { |ref_update| ref_update[:name] }.join(", ")}")
        end

        # Check that all ref updates refer to existing / valid commit oids
        commit_oids = []
        ref_updates.each do |ref_update|
          commit_oids << ref_update[:before_oid] if ref_update[:before_oid] && ref_update[:before_oid] != GitHub::NULL_OID
          commit_oids << ref_update[:after_oid] if ref_update[:after_oid] != GitHub::NULL_OID
        end

        begin
          repository.read_objects(commit_oids, "commit", feature_flag: :update_refs_read_objects_spokes_api)
        rescue GitRPC::ObjectMissing, GitRPC::InvalidObject => err
          raise Errors::Unprocessable.new(err.message)
        end

        # Load all refs so we can provide the before_oid in cases where the user did not provide one
        refs_by_refname = repository.refs.find_all(ref_updates.map { |ref_update| ref_update[:name] }).compact.index_by(&:qualified_name)
        forced_by_refname = ref_updates.map { |ref_update| [ref_update[:name], ref_update[:force] || false] }.to_h

        ref_updates = ref_updates.map do |ref_update|
          Git::Ref::Update.new(
            repository: repository,
            refname: ref_update[:name],
            before_oid: ref_update[:before_oid] || refs_by_refname[ref_update[:name]]&.target_oid || GitHub::NULL_OID,
            after_oid: ref_update[:after_oid]
          )
        end

        # TODO: Preload the fast-forwardness for all ref updates
        updates_by_commit_and_ancestor = ref_updates
          .reject   { |ref_update| ref_update.creation? || ref_update.deletion? }
          .group_by { |ref_update| [ref_update.after_oid, ref_update.before_oid] }

        results = repository.rpc.descendant_of(updates_by_commit_and_ancestor.keys)
        results.each do |commit_and_ancestor, is_descendant|
          updates_by_commit_and_ancestor[commit_and_ancestor].each do |ref_update|
            ref_update.fast_forward = is_descendant
          end
        end

        # TODO: Check that all ref updates that have `fast_forward` set to false
        #       also have `:force` set to true
        disallowed_non_fast_forwards = ref_updates.select do |ref_update|
          !ref_update.creation? && !ref_update.deletion? && !ref_update.fast_forward && !forced_by_refname[ref_update.refname]
        end

        if disallowed_non_fast_forwards.any?
          raise Errors::Unprocessable.new("rejecting non-fast forward update")
        end

        reflog_data = build_reflog_hash(context: context, via: "UpdateRefs mutation")

        # Rules are only supported by actual Repository objects, not by Gists or Wikis
        if repository.is_a?(Repository)
          rule_suites = RuleEngine::Evaluator.evaluate_rules(repository, ref_updates, context[:viewer])
          ref_updates.zip(rule_suites) do |ref_update, rule_suite|
            unless rule_suite.action_permitted?
              # TODO: create a new exception class that can wrap multiple failing decisions
              raise Errors::Unprocessable.new("Branch '#{ref_update.refname}' is protected: #{rule_suite.message}.")
            end
          end
        end

        # Try running pre-receive hooks
        if repository.has_pre_receive_hooks?
          # Get all ref updates that actually modify a ref
          modifying_ref_updates = ref_updates.select { |ref_update| ref_update.before_oid != ref_update.after_oid }
          reflines = modifying_ref_updates.map { |ref_update| "#{ref_update.before_oid} #{ref_update.after_oid} #{ref_update.refname}" }.join("\n")

          begin
            sockstat_data = reflog_data.merge(repo_pre_receive_hooks: repository.pre_receive_hooks.to_json).merge(repository.pre_receive_control_vars)
            result = repository.rpc.pre_receive_hook(reflines, GitHub::GitSockstat.new(sockstat_data).to_env)

            # XXX tests on linux are sometimes returning 127 (not found?)
            if result["status"] != 0 && result["status"] != 127
              raise Errors::Unprocessable.new("A Git pre-receive hook failed: #{[result["out"], result["err"]].join(" ")}.")
            end
          rescue GitRPC::SpawnFailure => e
            # if the hooks don't exist, that's then we don't have to run them
            raise Errors::Unprocessable.new("Could not execute pre-receive hooks. #{e.message}") unless e.message =~ /Errno::ENOENT/
          end
        end

        repository.batch_write_refs(context[:viewer], ref_updates.map(&:to_a), reflog: reflog_data, post_receive: true)

        {}
      end
    end
  end
end
