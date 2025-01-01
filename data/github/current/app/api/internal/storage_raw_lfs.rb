# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or acceping cached
# render blobs through the Alambic storage cluster. Used on GitHub Enterprise
# only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageRawLfs < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  include Api::App::ContentHelpers

  # Downloading objects for Render
  # See #verify_user and #parse_path_info! for @raw_* ivars
  get "/internal/storage/raw_lfs/:user/:repo/?*", operation_id: :internal do
    @route_owner = "@github/releases"
    parse_path_info!
    control_access :get_media_blob, resource: @raw_repo, repo: @raw_repo, allow_integrations: false, allow_user_via_granular_actor: false

    unless @raw_ref && @raw_path
      deliver_error!(404,
        message: "invalid ref from #{GitHub::JSON.encode @raw_full_path}")
    end

    blob = gitrpc do
      sha = @raw_repo.ref_to_sha(@raw_ref)
      tree_entry = sha.present? && @raw_repo.blob(sha, @raw_path)
      tree_entry && tree_entry.git_lfs? && ActiveRecord::Base.connected_to(role: :reading) { ::Media::Blob.fetch(@raw_repo, tree_entry.git_lfs_oid) }
    end

    if blob && blob.viewable?
      deliver :internal_storage_hash, blob, { origin: request.env["HTTP_ORIGIN"], env: request.env }
    else
      deliver_error(404, message: "blob: #{blob.inspect}")
    end
  end

  def verify_user(meta)
    parse_path_info!
    scope = RawBlob.scope(@raw_repo, @raw_ref, @raw_path)
    User.verify_signed_auth_token(token: @asset_token, scope: scope.to_s)
  end

  # Only needs to be called once. Can potentially be called in the sinatra
  # action, or #verify_user, which gets called early in sinatra's lifecycle
  # before params have been parsed. This is why the path info is parsed
  # manually.
  def parse_path_info!
    return if @raw_repo

    # "/internal/storage/raw_lfs/user/priv/branch/with/slash/images/taco-v2.jpg".split("/", 7)
    # => ["", "internal", "storage", "raw_lfs", "user", "priv", "branch/with/slash/images/taco-v2.jpg"]
    parts = storage_path_info.split("/", 7)
    repo = Repository.nwo("#{parts[4]}/#{parts[5]}")
    ref_sha_path_extractor = GitHub::RefShaPathExtractor.new(repo)
    branch, path = ref_sha_path_extractor.call(Api::LegacyEncode.decode(parts[6]))

    @raw_repo = repo
    @raw_ref = branch
    @raw_path = path
    @raw_full_path = parts[6]
  end
end
