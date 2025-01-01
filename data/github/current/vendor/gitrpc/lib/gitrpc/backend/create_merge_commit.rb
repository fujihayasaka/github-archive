# rubocop:disable Style/FrozenStringLiteralComment

module GitRPC
  class Backend
    SUBMODULE_MODE = 0160000

    def resolve_commit(rev)
      unless rev
        raise GitRPC::InvalidObject.new("revison does not exist")
      end

      if !sanitary_revspec?(rev)
        raise GitRPC::InvalidObject.new("not a valid revspec")
      end
      res = spawn_git("rev-parse", ["--verify", "--end-of-arguments", "#{rev}^{commit}"])
      if res["ok"]
        OpenStruct.new(oid: res["out"].rstrip)
      elsif res["err"].include?(NOT_GIT_REPO)
        raise GitRPC::InvalidRepository, "path is not a repository: #{@path}"
      elsif res["err"] =~ /but the object dereferences to (\w+) type/
        raise GitRPC::InvalidObject.new("type does not match - '#{rev}' is a #{$1}, not a commit")
      elsif valid_full_oid?(rev)
        raise GitRPC::ObjectMissing.new("object not found - no match for id (#{rev})", rev)
      else
        raise GitRPC::InvalidObject.new("'#{rev}' is not a valid revision")
      end
    end

    rpc_writer :create_merge_commit
    def create_merge_commit(*args)
      dogstats = (args[5] || {})[:dogstats] ? [["merge_tree.failure", 1, { tags: ["status:failure"] }]] : nil
      begin
        options, err, details = create_merge_commit_options(*args)
        dogstats = options[:dogstats] unless options[:dogstats].nil?
        return [nil, err, details, nil, dogstats] unless err.nil?

        commit_oid = create_commit(options, false)
        [commit_oid, nil, nil, nil, dogstats]
      rescue Rugged::IndexError
        # Errors when building the index count as merge conflicts
        [nil, "merge_conflict", nil, nil, dogstats]
      rescue Rugged::TreeError => e
        [e.to_s, "error", nil, nil, dogstats]
      end
    end

    rpc_writer :stage_signed_merge_commit
    def stage_signed_merge_commit(*args)
      dogstats = (args[5] || {})[:dogstats] ? [["merge_tree.failure", 1, { tags: ["status:failure"] }]] : nil
      begin
        options, err, details = create_merge_commit_options(*args)
        dogstats = options[:dogstats] unless options[:dogstats].nil?
        return [nil, err, details, nil, dogstats] unless err.nil?

        commit_content = create_commit(options, true)
        [commit_content, nil, nil, options[:tree], dogstats]
      rescue Rugged::IndexError
        # Errors when building the index count as merge conflicts
        [nil, "merge_conflict", nil, nil, dogstats]
      rescue Rugged::TreeError => e
        [e.to_s, "error", nil, nil, dogstats]
      end
    end

    rpc_writer :persist_signed_merge_commit
    def persist_signed_merge_commit(base_data, signature, *args)
      dogstats = (args[5] || {})[:dogstats] ? [["merge_tree.failure", 1, { tags: ["status:failure"] }]] : nil
      begin
        # ensure that any blobs/trees are created on all replicas.
        options, err, details = create_merge_commit_options(*args)
        dogstats = options[:dogstats] unless options[:dogstats].nil?
        return [nil, err, details, nil, dogstats] unless err.nil?

        commit_oid = create_commit_with_signature_raw(base_data, signature)
        [commit_oid, nil, nil, nil, dogstats]
      rescue Rugged::IndexError
        # Errors when building the index count as merge conflicts
        [nil, "merge_conflict", nil, nil, dogstats]
      rescue Rugged::TreeError => e
        [e.to_s, "error", nil, nil, dogstats]
      end
    end

    def prettify_message(message, options = {})
      Rugged.prettify_message(message, false)
    end

    def create_merge_commit_options(base, head, author, commit_message, committer = nil, opts = {}, return_tree = false)
      record_conflicts = opts[:record_conflicts] || false
      resolve_conflicts = opts[:resolve_conflicts] || {}
      max_conflicts = opts[:max_conflicts] || 25
      more_conflict_info = opts[:more_conflict_info]

      base = resolve_commit(base)
      head = resolve_commit(head)

      author = symbolize_keys(author)
      author[:time] = iso8601(author[:time])

      committer ||= author
      committer = symbolize_keys(committer)
      committer[:time] = iso8601(committer[:time])

      # If the caller already knows which tree they want and we have it, we can
      # return immediately.
      tree = opts[:tree]
      if valid_full_oid?(tree) && tree_is_complete?(tree, base_oid: base.oid)
        options = {
          :message    => commit_message,
          :committer  => committer,
          :author     => author,
          :parents    => [base, head],
          :tree       => tree,
        }
        options[:dogstats] = [["merge_tree.dogstats.failure", 1, { tags: ["status:failure"] }]] if opts[:dogstats]

        return [options, nil]
      end

      merge_options = {
        :fail_on_conflict => !record_conflicts && resolve_conflicts.empty?,
        :skip_reuc => true,
        :no_recursive => true,
        :renames => false,
        :dogstats => opts[:dogstats],
        :use_tmp_objdir_mode => opts[:use_tmp_objdir_mode],
        :keep_unpacked_threshold => opts[:keep_unpacked_threshold],
      }

      # Write out resolutions as blobs
      resolving_oids = resolve_conflicts.each_with_object({}) do |(path, content), acc|
        acc[path] = rugged.write(content, :blob)
      end

      tree, conflicts, err, dogstats = merge_tree(
        base: base,
        head: head,
        merge_options: merge_options,
        resolutions: resolving_oids
      )

      return [{ dogstats: dogstats }, err, nil] if err
      return [{ dogstats: dogstats }, "merge_conflict", nil] if !tree && !conflicts

      if !tree && conflicts
        if record_conflicts
          formatted_conflicts = {}
          maxed_out = false
          count = 0
          conflicts.each do |ci|
            filename = (ci[:ours] || ci[:theirs])[:path]
            # for now, we only really handle simple conflicts, so we're not
            # storing filename or mode changes. we can just add them here
            # later if we need it.
            formatted_conflicts[filename] = {
              :base => nil,
              :head => nil,
              :ancestor => nil,
            }

            if ci[:theirs]
              oid = ci[:theirs][:oid]
              if more_conflict_info && ci[:theirs][:mode] != SUBMODULE_MODE
                blob, = read_blobs([oid])
              else
                blob = nil
              end
              info = formatted_conflicts[filename][:base] = {
                :oid => oid,
              }

              if blob
                info[:file_size] = blob["size"]
                info[:binary] = blob["binary"]
              end
            end

            if ci[:ours]
              oid = ci[:ours][:oid]
              if more_conflict_info && ci[:ours][:mode] != SUBMODULE_MODE
                blob, = read_blobs([oid])
              else
                blob = nil
              end
              info = formatted_conflicts[filename][:head] = {
                :oid => oid,
              }

              if blob
                info[:file_size] = blob["size"]
                info[:binary] = blob["binary"]
              end
            end

            if ci[:ancestor]
              oid = ci[:ancestor][:oid]
              if more_conflict_info && ci[:ancestor][:mode] != SUBMODULE_MODE
                blob, = read_blobs([oid])
              else
                blob = nil
              end
              info = formatted_conflicts[filename][:ancestor] = {
                :oid => oid,
              }

              if blob
                info[:file_size] = blob["size"]
                info[:binary] = blob["binary"]
              end
            end

            formatted_conflicts[filename][:type] =  if ci[:ours] && ci[:theirs]
              # file exists in both revisions
              if ci[:ours][:mode] == SUBMODULE_MODE || ci[:theirs][:mode] == SUBMODULE_MODE
                :submodule_conflict
              elsif ci[:ours][:mode] != ci[:theirs][:mode]
                :mode_conflict
              elsif ci[:ours][:filename] != ci[:theirs][:filename]
                :filename_conflict
              else
                :regular_conflict
              end
            else
              # file only exists in one revision
              ci[:ours] ? :not_in_theirs : :not_in_ours
            end
            count = count + 1
            if count >= max_conflicts
              maxed_out = true
              break
            end
          end

          return [{ dogstats: dogstats }, "merge_conflict", {
              :base => base.oid,
              :head => head.oid,
              :conflicted_files => formatted_conflicts,
              :more_conflicted_files => maxed_out
            }]
        else
          return [{ dogstats: dogstats }, "merge_conflict", nil]
        end
      end

      options = {
        :message    => commit_message,
        :committer  => committer,
        :author     => author,
        :parents    => [base, head],
        :tree       => tree,
      }
      options[:dogstats] = dogstats if opts[:dogstats]

      [options, nil, nil]
    end

    def tree_is_complete?(oid, base_oid:)
      # If we can diff the tree against base, then it and all its descendants should be good.
      res = spawn_git("diff", ["--raw", "#{base_oid}..#{oid}"])
      res["ok"]
    end
  end
end
