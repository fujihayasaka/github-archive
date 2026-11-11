# typed: true
# frozen_string_literal: true

class Api::GitBlobs < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::RepositoryRulesDependency

  MAX_BLOB_SIZE = 100.megabytes.freeze

  # Get the contents of a blob object
  get "/repositories/:repository_id/git/blobs/:sha", operation_id: "git/get-blob" do
    control_access :get_blob,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)

    begin
      blob = repo.blob_by_oid(sha_param!(:sha))
    rescue GitRPC::ObjectMissing, GitRPC::InvalidObject
      deliver_error!(404)
    end

    deliver_too_large_error! if blob.size > MAX_BLOB_SIZE

    max_age = 86400 # one day in seconds

    if medias.api_param?(:raw)
      deliver_raw blob.raw_data, content_type: blob.raw_content_type, max_age: max_age
    else
      deliver :grit_blob_hash, blob, repo: repo, max_age: max_age
    end
  end

  # Create a new blob object
  post "/repositories/:repository_id/git/blobs", operation_id: "git/create-blob", read_from_replicas: true do
    control_access :create_blob,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    authorize_content(:create, repo: repo)
    ensure_repo_content!(repo)
    ensure_repo_writable!(repo)

    with_write(clusters: [ApplicationRecord::RepositoriesPushes, ApplicationRecord::Repositories, ApplicationRecord::Spokes]) do
      # Introducing strict validation of the git-blob.create
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      data = receive_with_schema("git-blob", "create", skip_validation: true)
      content = data["content"]

      unless content
        deliver_error!(422,
          errors: [api_error(:Blob, :content, :missing_field)],
          documentation_url: @documentation_url)
      end

      unless content.is_a?(String)
        deliver_error!(422,
          message: "content must be a string",
          errors: [api_error(:Blob, :content, :invalid)],
          documentation_url: @documentation_url)
      end

      if data["encoding"] == "base64"
        content = Base64.decode64(content)
      end

      sha = begin
        event = RuleEngine::Events::PreBlobEvent.new(repo, current_user, metadata: { blobs: { "" => content } })
        rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)

        raise Git::Ref::RepositoryRuleViolationError.new(rule_suite) unless rule_suite.action_permitted?

        repo.rpc.write_blob(content)
      rescue Git::Ref::RepositoryRuleViolationError => e
        halt deliver_rule_violation_error(e, 422)
      rescue GitRPC::RequestTooLarge
        deliver_error!(422,
          message: "Sorry, your input was too large to process. Consider creating the blob " \
                  "in a local clone of the repository and then pushing it to GitHub.")
      end

      blob = {
        sha: sha,
        url: api_url("/repos/#{repo.name_with_display_owner}/git/blobs/#{sha}"),
      }

      deliver_raw blob, repo: repo, status: 201
    end
  end

  private

  def api_url(suffix)
    Api::Serializer.url(suffix)
  end

  def deliver_too_large_error!
    deliver_error! 403,
      message: "This API returns blobs up to 100 MB in size. "\
        "The requested blob is too large to fetch via the API, "\
        "but you can always clone the repository via Git in order to obtain this blob.",
      errors: [api_error(:Blob, :data, :too_large)],
      documentation_url: "/v3/git/blobs/#get-a-blob"
  end

  def authorize_content(operation = :create, data = {})
    authorization = ContentAuthorizer.authorize(current_user, :blob, operation, data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end
end
