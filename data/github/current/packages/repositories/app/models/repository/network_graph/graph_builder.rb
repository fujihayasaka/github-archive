# typed: false
# frozen_string_literal: true

class Repository::NetworkGraph
  class GraphBuilder
    include Scientist
    DEFAULT_TIME_SLICE = 200

    def initialize(repo, network_hash)
      @repo = repo
      @network_hash = network_hash
    end

    def build
      shas, commits, users = construct_data_import

      business = @repo.enterprise_managed_business if @repo.is_enterprise_managed?
      attach_users_to_commits commits, business: business

      user_blocks, space_map = construct_calculate_spaces(shas, commits, users)

      commits_data, index_data = construct_generate_commit_blobs(construct_commit_data(shas, commits))
      meta_data = construct_meta(@repo, shas, commits, users, user_blocks, space_map)
      [meta_data, index_data, commits_data]
    end

    def self.extract_commits(index, data, focus, start_time, end_time)
      return [] if data.bytesize == 0

      commit_count = index.size / 4

      end_time ||= focus + (DEFAULT_TIME_SLICE / 2)
      end_time = commit_count - 1 if end_time > commit_count

      start_time ||= end_time - DEFAULT_TIME_SLICE
      start_time = 0 if start_time < 0

      # Find position of first commit. If the index can't be extracted, it's
      # probably a client requesting an old data time value.
      commits = []
      if start_position = index[start_time * 4, 4]
        start_position = start_position.unpack("L").first

        # read the commits
        f = StringIO.new(data)
        f.seek(start_position)
        (end_time - start_time + 1).times do
          first_bytes = f.read(4)
          next unless first_bytes # Don't continue without data

          size = first_bytes.unpack("L").first
          mcommit = f.read(size)
          hcommit = Marshal.load(mcommit)
          commits << hcommit
        end
      end
      commits
    end

    private

    # Batch loads all User objects for the author and/or committer emails
    # in the commits Array, and assigns the user attributes for each.
    #
    # commits  - Array of Commit objects
    # business - an emu business associated with the email
    #
    # Returns Array of commits, but with author and committer users filled in.
    def attach_users_to_commits(commits, business: nil)
      emails = Set.new
      commits.each do |commit|
        emails << commit.author_email    if !commit.author_email.blank?
        emails << commit.committer_email if !commit.committer_email.blank?
      end

      users = User.find_by_emails(emails.to_a, business: business)
      commits.each do |commit|
        author, committer = commit.author_email, commit.committer_email
        commit.author     = (users[author.downcase] if author)
        commit.committer  = (users[committer.downcase] if committer)
      end
    end

    def construct_meta(repo, shas, commits, users, user_blocks, space_map)
      dates = commits.map { |c| c.committed_date.strftime("%Y-%m-%d") }

      # Focus on default branch (always first in heads)
      heads = users.first["heads"]
      head  = heads.first
      focus = shas[head["id"]]&.time_position || 0

      { "users" => users,
        "dates" => dates,
        "blocks" => user_blocks,
        "focus" => focus,
        "nethash" => @network_hash,
        "spacemap" => space_map }
    end

    # This method does most of the tedious heavy-lifting to prepare the graph.
    #
    # Loads commits for every repository in the network into the internal state
    # variables: shas and commits. The shas Hash maps commit SHA1s to Commit
    # objects. The commits Array holds a list of commits in graph order.
    def construct_data_import
      shas = {}
      commits = []
      users = []
      network_commits = []
      network_heads = Set.new
      history_limit = GitHub.network_graph_history_limit

      logins = {}
      User.where(id: network_repos.map(&:owner_id).uniq).each do |user|
        logins[user.id] = user.display_login
      end

      network_repos.each do |r|
        next if r.empty? || !r.online?

        retried_already = false

        begin
          default_ref = "refs/heads/#{r.default_branch}"
          raw_heads = [default_ref]

          branch_names_and_dates = r.rpc.raw_branch_names_and_dates
          GitHub.dogstats.count("network_graphs.size", branch_names_and_dates.size, tags: ["branches"])
          branch_names_and_dates.reverse_each do |_date, ref|
            next if ref == default_ref
            raw_heads << ref
            break if raw_heads.size == GitHub.network_graph_branch_limit
          end

          heads = r.refs.find_all(raw_heads).compact.map do |ref|
            { "name" => ref.name, "id" => ref.target_oid }
          end

          additions = heads.select { |head| !shas.include?(head["id"]) }
          if additions.any?
            head_ids = additions.map { |h| h["id"] }
            # This repository might not have all the commits from other
            # repositories in the network, so filter down to valid commits
            # for this repository.
            except   = r.rpc.expand_shas(network_heads.to_a, "commit").values
            r.commits.except(head_ids, except, history_limit).each do |commit|
              commit = Repository::NetworkGraph::Commit.new(commit)
              next if shas.include?(commit.oid)
              shas[commit.oid] = commit
              network_commits << commit
            end
            network_heads.merge heads.map { |h| h["id"] }

            users << { "name" => logins[r.owner_id], "repo" => r.name, "heads" => heads }
          end
        rescue GitRPC::CommandFailed, Repository::CommandFailed => err
          if retried_already
            raise err
          else
            network_heads = Set.new
            network_commits = []

            retried_already = true
            retry
          end
        end
      end

      roots = []

      # add children to each commit
      network_commits.each do |c|
        c.drawn = false
        c.timestamp = c.committed_date.to_i
        c.parent_oids.reject! { |oid| !shas.include?(oid) }

        roots << c if c.parent_oids.empty?

        c.parent_oids.each do |oid|
          shas[oid].add_child(c)
        end
      end

      # order commits by graph structure
      i = 0
      commit_time_position = 0
      candidates = roots.sort_by { |x| x.timestamp }
      while !candidates.empty?
        # find the first commit that has no pending dependencies
        found = false

        candidates.each do |candidate|
          if candidate.parent_oids.all? { |oid| shas[oid].time_position }
            candidate.time_position = commit_time_position
            commit_time_position += 1
            commits << candidate
            candidates.delete(candidate)
            if candidate.children
              candidate.children.each { |child| candidates << child }
              candidates = candidates.sort_by { |x| x.timestamp }
            end
            found = true
            break
          end
        end

        raise("Unable to assemble consistent graph") unless found

        i += 1
        break if i > network_commits.size
      end
      [shas, commits, users]
    end

    def construct_calculate_spaces(shas, commits, users)
      user_blocks = []
      space_map = []
      user_space_min = 0
      users.each do |user|
        user_block = construct_calculate_spaces_user(shas, space_map, user_space_min, user)
        if user_block
          user_blocks << user_block
          user_space_min = space_map.size
        end
      end
      [user_blocks, space_map]
    end

    def construct_calculate_spaces_user(shas, space_map, user_space_min, user)
      # Remember the space position we started at. It will be used later to
      # calculate how many space rows this user inhabits.
      start_space_position = space_map.size

      # Pending paths is an Array of Arrays where each inner Array is comprised
      # of a Commit at index zero and something that is never used at index one.
      pending_paths =
      user["heads"].map do |head|
        shas[head["id"]]
      end.compact.map do |head|
        [head, nil]
      end

      # If this user has no unique heads, then we're done.
      return if pending_paths.empty?

      # Shift a path off the pending_paths array. If the commit has already been
      # drawn, ignore it. Otherwise calculate the paths for these commits and
      # add them to pending_paths array so that they may be used as the base for
      # discovery of other paths.
      additions = false
      begin
        c, p = *pending_paths.shift
        unless c.drawn
          additions = true
          additional_paths = construct_calculate_spaces_path(shas, space_map, user_space_min, c, p, user)
          pending_paths = additional_paths + pending_paths
        end
      end while pending_paths.size > 0 # rubocop:disable Lint/Loop

      # If any new paths were added, return a section to record the details.
      if additions
        num_spaces = space_map.size - start_space_position
        { "name" => user["name"],
                 "start" => start_space_position,
                 "count" => num_spaces }
      end
    end

    # A path is an array of Commits representing a single linear history of a
    # specific commit.
    #
    # c - The Commit from which to start the traversal.
    # p - If not nil, is the child merge Commit of `c`. This must be set
    #     for non-head commits.
    #
    # Returns an Array of Arrays of [<Commit>, <Commit>] represnting the
    #   additional path heads to be processed.
    def construct_calculate_spaces_path(shas, space_map, user_space_min, c, p, user)
      additional_paths = []
      path_commits = []

      this_commit = c

      # Populate the path_commits array with a list of Commits that will make up
      # this path.
      while this_commit
        path_commits << this_commit
        prev_commit = nil

        # A commit with more than one parent (a merge commit) will trace its
        # first parent. Any other parents are added to the additional_paths
        # for later processing. Parents that have already been drawn will be
        # ignored.
        this_commit.parent_oids.each do |oid|
          pc = shas[oid]
          if pc.drawn
            # ignore it
          else
            if prev_commit
              additional_paths << [pc, this_commit]
            else
              prev_commit = pc
            end
          end
        end

        # Iterate. The path is complete if (a) the current commit has no parents
        # or (b) all parents have already been drawn.
        this_commit = prev_commit
      end

      # If a child merge commit was specified, that is the upper bound,
      # otherwise the upper bound is the first commit in the path array.
      upper_bound_source = p ? p : path_commits.first
      upper_bound = upper_bound_source.time_position

      # If the last commit in the path has at least one parent, the first
      # parent becomes the lower bound, otherwise the last commit itself
      # becomes the lower bound.
      lower_bound_source =
      if path_commits.last.parent_oids.first
        path_commits.last.parent_oids.
          map  { |oid| shas[oid] }.
          sort { |a, b| a.time_position <=> b.time_position }.
          first
      else
        path_commits.last
      end
      lower_bound = lower_bound_source.time_position

      # Find the space position for this span, assign it to each commit, and
      # mark the commit as drawn.
      space_position = construct_calculate_spaces_place_space_span(space_map, user_space_min, lower_bound, upper_bound)
      path_commits.each do |c|
        c.space_position = space_position
        c.drawn = true
      end

      additional_paths
    end

    # Place the given span into the space map.
    #
    # lower_bound - The lower bound Integer time position of the span.
    # upper_bound - The upper bound Integer time position of the span.
    #
    # Returns the space position Integer.
    def construct_calculate_spaces_place_space_span(space_map, user_space_min, lower_bound, upper_bound)
      space_position = construct_calculate_spaces_find_lowest_space_position(space_map, user_space_min, lower_bound, upper_bound)

      space_map[space_position] ||= []
      space_map[space_position] << [lower_bound, upper_bound]

      space_position
    end

    # Find the lowest space position (vertical dimension) that will acommodate
    # the given span.
    #
    # lower_bound - The lower bound Integer time position of the span.
    # upper_bound - The upper bound Integer time position of the span.
    #
    # Returns the lowest space position index Integer.
    def construct_calculate_spaces_find_lowest_space_position(space_map, user_space_min, lower_bound, upper_bound)
      # The first time this is called, the space map will be empty, so we can
      # just retun the default user_space_min.
      if space_map[user_space_min].nil?
        return user_space_min
      end

      # Iterate over each space this user currently inhabits. For each space,
      # test for a collision with the existing paths in that space. If a space
      # is found that contains no collisions, return it, otherwise return the
      # size of the space map (which yields the next largest space map index).
      (user_space_min...space_map.size).each do |i|
        space_available = true

        space_map[i].each do |span|
          if construct_calculate_spaces_paths_collide?([lower_bound, upper_bound], span)
            space_available = false
            break
          end
        end

        return i if space_available
      end

      space_map.size
    end

    # Do the two paths collide with each other (overlap)?
    #
    # a - The [LowerInt, UpperInt] Array of one path.
    # b - The [LowerInt, UpperInt] Array of the other path.
    #
    # Returns Bool
    def construct_calculate_spaces_paths_collide?(a, b)
      construct_calculate_spaces_time_in_path?(a[0], b) ||
      construct_calculate_spaces_time_in_path?(a[1], b) ||
      construct_calculate_spaces_time_in_path?(b[0], a) ||
      construct_calculate_spaces_time_in_path?(b[1], a)
    end

    # Is the given time in the given path?
    #
    # time - The time Integer.
    # path - The [LowerInt, UpperInt] Array of the path.
    #
    # Returns Bool
    def construct_calculate_spaces_time_in_path?(time, path)
      time >= path[0] && time <= path[1]
    end

    def construct_generate_commit_blobs(hcommits)
      pointer = 0
      fdata = StringIO.new
      findex = StringIO.new
      if fdata.respond_to?(:set_encoding)
        fdata.set_encoding("binary")
        findex.set_encoding("binary")
      end

      hcommits.each do |hcommit|
        findex.write([pointer].pack("L"))

        mcommit = Marshal.dump(hcommit)
        msize = mcommit.bytesize
        fdata.write([msize].pack("L"))
        fdata.write(mcommit)

        pointer += msize + 4
      end
      [fdata.string, findex.string]
    end

    # Construct the actual JSON object that we use in constructing netgraphs.
    def construct_commit_data(shas, commits)
      commits.map do |c|
        parents = c.parent_oids.map do |oid|
          pc = shas[oid]
          [pc.oid, pc.time_position, pc.space_position]
        end

        { "id"       => c.oid,
          "parents"  => parents,
          "message"  => c.short_message,
          "author"   => c.author_name,
          "login"    => c.author&.display_login || c.author.to_s,
          "date"     => c.committed_date.strftime("%Y-%m-%d %H:%M:%S"),
          "gravatar" => avatar_for(c.author),
          "space"    => c.space_position,
          "time"     => c.time_position }
      end
    end

    def avatar_for(author)
      author ? author.primary_avatar_url(64) : ""
    end

    # Return the repos associated with the network using #network_repos_for.
    # Don't include private repos, repos where the original repo owner owns
    # the associated repo, repos that have not been pushed to. Finally,
    # sort the repos by how many stars they have and when they were most
    # recently pushed to.
    def network_repos
      return [] if !@repo
      @network_repos ||= begin
        other_repos = @repo.network_repositories.not_spammy
        other_repos = other_repos
          .where(["repositories.pushed_at > repositories.created_at AND repositories.id <> ?", @repo.id])
          .order("repositories.pushed_at DESC")
          .limit(GitHub.network_graph_fork_limit)
          .to_a

        if @repo.private? && @repo.owner.user?
          # Fetch and filter other_repos asynchronously
          Promise.all(other_repos.map { |repo| repo.async_pullable_by?(@repo.owner) }).then do |results|
            other_repos.select!.with_index { |_repo, index| results[index] }

            # Return an array including the base repo, as well as the other repos.
            [@repo] + other_repos
          end.sync
        else
          # Return an array including the base repo and all other repos
          [@repo] + other_repos
        end
      end
    end
  end
end
