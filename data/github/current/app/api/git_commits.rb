# typed: strict
# frozen_string_literal: true

class Api::GitCommits < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::GitActorHelpers

  # Get the contents of a commit object
  get "/repositories/:repository_id/git/commits/:commit_id", operation_id: "git/get-commit" do
    control_access :get_commit,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)

    begin
      commit = Repositories.domain.commits.by_oid(repository: repo, commit_oid: params[:commit_id])
    rescue GitRPC::InvalidObject,
           GitRPC::ObjectMissing,
           RepositoryObjectsCollection::InvalidObjectId
      deliver_error!(404)
    end
    deliver :commit_hash, commit, repo: repo, last_modified: calc_last_modified_for_object(commit)
  end

  # Create a new commit object
  post "/repositories/:repository_id/git/commits", operation_id: "git/create-commit", read_from_replicas: true do
    control_access :create_commit,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    ensure_repo_content!(repo)
    ensure_repo_writable!(repo)

    data = receive_with_schema("git-commit", "create-legacy")

    # message, tree are mandatory
    message = data["message"]
    tree    = sha_param!("tree", data)

    signature = data["signature"]

    # check tree
    begin
      if !(_tree_obj = repo.objects.read(tree, "tree"))
        deliver_error!(422, message: "Tree SHA is not an object")
      end

      rescue GitRPC::ObjectMissing
        deliver_error!(422, message: "Tree SHA does not exist")
      rescue GitRPC::InvalidObject
        deliver_error!(422, message: "Tree SHA is not a tree object")
    end

    # check parents
    parents = Array(data["parents"])
    begin
      if !repo.commits.exist?(parents)
        deliver_error!(422,
          message: "Parent SHA does not exist or is not a commit object")
      end
    rescue RepositoryObjectsCollection::InvalidObjectId
      # message adapted from sha_param! method above
      deliver_error!(422,
        message: "Each SHA in the 'parents' parameter must be exactly 40 characters and contain only [0-9a-f].")
    end

    info = {
      "tree"    => tree,
      "message" => message,
    }

    default_time = Time.zone.now.iso8601
    default_actor = GitActor.new(
      name: current_user.git_author_name,
      email: current_user.git_author_email,
      time: default_time,
    )
    web_committer = GitActor.new(
      name: GitHub.web_committer_name,
      email: GitHub.web_committer_email,
      time: default_time,
    )

    # Determine whether the commit should be automatically signed by GitHub's
    # web committer.
    #
    # If the content creator is a bot and neither the committer nor the author
    # are specified, we can sign the commit with confidence. We're choosing
    # (for now) not to sign bot-created commits authored on behalf of a user.
    sign_commit = GitHub.web_commit_signing_enabled? &&
      current_user.bot? &&
      data["author"].nil? &&
      data["committer"].nil? &&
      signature.nil?

    author = if data["author"]
      git_actor!(data, key: "author", default_time: default_time)
    else
      default_actor
    end
    info["author"] = author.to_gitrpc_hash

    committer = if sign_commit
      web_committer
    elsif data["committer"]
      git_actor!(data, key: "committer", default_time: default_time)
    else
      author
    end
    info["committer"] = committer.to_gitrpc_hash

    begin
      rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(
        repo,
        # In the case of a merge commit, we want the topic branch which is usually the last parent in the list.
        parents.last || GitHub::NULL_OID,
        current_user,
        {
          message:,
          author_email: author.email,
          committer_email: committer.email,
          blobs: {},
        }
      )

      raise Git::Ref::RepositoryRuleViolationError.new(rule_suite) unless rule_suite.action_permitted?

      sha = Repositories.domain.commits.create_tree_changes(
        repository: repo,
        parent_oids: parents,
        info: info,
        files: nil,
        sign_commit: sign_commit,
        signature: signature
      )

      commit = Repositories.domain.commits.by_oid(repository: repo, commit_oid: sha)

      with_write(clusters: [ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::RepositoriesPushes]) do
        if commit && rule_suite.persisted?
          rule_suite.after_oid = commit.oid
          rule_suite.save!
        end
      end
    rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
      deliver_error!(404)
    rescue GitRPC::BadGitmodules, GitRPC::SymlinkDisallowed => e
      deliver_error!(422, message: e.to_s)
    rescue Git::Ref::RepositoryRuleViolationError => e
      deliver_error!(422, message: e.detailed_message)
    end

    deliver :commit_hash, commit, repo: repo, status: 201
  end
end
