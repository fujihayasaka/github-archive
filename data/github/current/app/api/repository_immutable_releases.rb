# typed: true
# frozen_string_literal: true

class Api::RepositoryImmutableReleases < Api::App
  include ReceiveSchemaWithOpenApi

  # check the status of the immutable releases setting
  get "/repositories/:repository_id/immutable-releases", operation_id: "repos/check-immutable-releases" do
    @accepted_scopes = %(repo)
    repo = find_repo!
    config = Releases::ImmutableRepositoryConfig.new(repo)

    ensure_feature_flag_enabled!(repo)

    control_access(:read_repo_immutable_releases,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    hash = {
      enabled: config.immutable_releases_enabled?,
      enforced_by_owner: config.immutable_releases_enforced_by_owner?,
    }
    deliver(:raw, hash)
  end

  # enable immutable releases for a repo
  put "/repositories/:repository_id/immutable-releases", operation_id: "repos/enable-immutable-releases", read_from_replicas: true do
    @accepted_scopes = %(repo)
    repo = find_repo!
    config = Releases::ImmutableRepositoryConfig.new(repo)

    ensure_feature_flag_enabled!(repo)

    control_access(:edit_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    # There's no request body for this endpoint, but we still want to validate
    # the request against the schema to return an error if there are
    # unexpected parameters.
    receive_with_schema("repository-immutable-releases-setting", "enable")

    if config.immutable_releases_enforced_by_owner?
      deliver_error!(409, message: "Immutable releases are enforced by the repository owner.")
    else
      with_write(clusters: [ApplicationRecord::Configurations]) do
        config.enable_immutable_releases(actor: current_user)
        deliver_empty(status: 204)
      end
    end
  end

  # disable immutable releases for a repo
  delete "/repositories/:repository_id/immutable-releases", operation_id: "repos/disable-immutable-releases", read_from_replicas: true do
    @accepted_scopes = %(repo)
    repo = find_repo!
    config = Releases::ImmutableRepositoryConfig.new(repo)

    ensure_feature_flag_enabled!(repo)

    control_access(:edit_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    # There's no request body for this endpoint, but we still want to validate
    # the request against the schema to return an error if there are
    # unexpected parameters.
    receive_with_schema("repository-immutable-releases-setting", "disable")

    if config.immutable_releases_enforced_by_owner?
      deliver_error!(409, message: "Immutable releases are enforced by the repository owner.")
    else
      with_write(clusters: [ApplicationRecord::Configurations]) do
        config.disable_immutable_releases(actor: current_user)
        deliver_empty(status: 204)
      end
    end
  end

  private

  sig { params(repo: Repository).void }
  def ensure_feature_flag_enabled!(repo)
    unless repo.feature_enabled_for_repo_or_owner?(:immutable_releases)
      deliver_error! 404
    end
  end
end
