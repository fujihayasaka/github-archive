# typed: true
# frozen_string_literal: true

# The `TokenValidAfterManager` class is responsible for estimating the time at which different types
# of installation tokens become valid.
#
# Behind the scenes, it uses the `default_replication_wait` method to obtain the replication delay
# on the permissions and collab clusters.
class TokenValidAfterManager
  STATS_KEY = "apps.token_valid_after_manager.delay"
  FRESH_INSTALLATION_TRESHOLD = 10.seconds

  def initialize(installation, using_cached_installation: false)
    @installation = installation
    @using_cached_installation = using_cached_installation
    @tags = ["token_type:#{token_type}", "cached_installation:#{using_cached_installation?}"]
  end

  # This method calculates the timestamp at which a given installation token become valid.
  #
  # The calculation takes into consideration a few factors:
  # - Installation freshness and cached status
  # - Replication delay on the permissions and collab clusters.

  # It uses Time.now.to_f to obtain a high-precision timestamp, rather than the created_at timestamps
  # which have lower precision (seconds).
  def valid_after
    delay = valid_after_delay
    GitHub.dogstats.distribution(STATS_KEY, delay, tags: @tags)
    Time.now.to_f + (delay / 1000.0)
  end

  private

  def valid_after_delay
    clusters_delay = { permissions: permissions_valid_after_delay, collab: collab_valid_after_delay }
    delaying_cluster = clusters_delay.key(clusters_delay.values.max)
    @tags << "delaying_cluster:#{delaying_cluster}"
    clusters_delay[delaying_cluster]
  end

  def permissions_valid_after_delay
    # If the installation is cached, we can assume that the permissions are already replicated to
    # the permissions cluster.
    return 0.0 if using_cached_installation?

    # In the case of IntegrationInstallations, permissions are usually already in sync with the permissions cluster.
    # However, there is an exception in the case of newly created installations, especially but not limited to
    # those created via the Automatic Installations Pipeline. Here's an example:
    #
    # - A new workflow file is added to a repository that doesn't have actions enabled yet.
    # - The addition of the workflow file triggers the Automatic Installations pipeline.
    # - This pipeline, in turn, creates an IntegrationInstallation record.
    # - Thereafter, Launch issues a token request for the recently created IntegrationInstallation record.
    # - It's possible that the permissions for this IntegrationInstallation are not yet replicated to the permissions cluster.
    #
    # In this scenario, the "freshness" of the IntegrationInstallation is used to determine
    # if fetching the current permissions delay is necessary.
    return 0.0 if @installation.is_a?(IntegrationInstallation) && !fresh_installation?

    # For all other cases, we need to take into account the replication delay on the permissions cluster.
    current_permissions_replication_delay
  end

  def collab_valid_after_delay
    return 0.0 unless FeatureFlag.vexi.enabled?(:valid_after_manager_collab_replication_delay, default: false)

    current_collab_replication_delay
  end

  def current_permissions_replication_delay
    # default_replication_wait will actually return the "current" replication
    # wait time in milliseconds as observed by Freno.
    #
    # The underlying method is already handling Freno errors.
    ApplicationRecord::Permissions.default_replication_wait
  end

  def current_collab_replication_delay
    ApplicationRecord::Collab.default_replication_wait
  end

  def token_type
    @installation.class.name.demodulize.underscore
  end

  def using_cached_installation?
    !!@using_cached_installation
  end

  def fresh_installation?
    @installation.created_at > FRESH_INSTALLATION_TRESHOLD.ago
  end
end
