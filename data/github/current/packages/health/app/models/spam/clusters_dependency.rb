# typed: true
# frozen_string_literal: true

module Spam::ClustersDependency

  # Cluster Users into groups by the temporal proximity of their
  # creation times (or other specified attribute; see below).
  #
  # u      = Array of Users (typically sharing the same last_ip address)
  # params = Optional Hash of params, which may include:
  #   :attr    = Attribute to use for comparison. Defaults to :created_at.
  #   :gap     = Max value to use as the cluster gap. Defaults to the
  #              number of seconds in 72.hours.
  #   :verbose = Produce output during operation (for console use).
  #              Defaults to false.
  #
  # Returns an Array of Arrays of User objects, grouped by the
  # interval between their created_at data.
  def build_clusters(u, params = nil)
    params ||= {}
    cluster_gap = params[:gap] || 72.hours
    cluster_attr = params[:attr] || :created_at
    verbose = params[:verbose]

    intervals = []
    clusters = []
    current_cluster = []

    u.find_each do |user|
      if last_user = current_cluster.last
        Rails.logger.info "First #{last_user.id}: #{last_user.send(cluster_attr)} \tSecond #{user.id}: #{user.send(cluster_attr)}" if verbose
        # Store the interval between this and the last's creation
        this_interval = user.send(cluster_attr) - last_user.send(cluster_attr)
        intervals << this_interval
        Rails.logger.info "Interval is #{this_interval}, which is #{this_interval > cluster_gap ? 'greater than' : 'less than or equal to'} #{cluster_gap}" if verbose
        if this_interval > cluster_gap
          Rails.logger.info "Interval is above gap. Adding." if verbose
          Rails.logger.info "Clusters before: #{clusters.size} and current_cluster size: #{current_cluster.size}" if verbose
          clusters << current_cluster.dup
          current_cluster = []
          Rails.logger.info "Clusters after: #{clusters.size} and current_cluster size: #{current_cluster.size}" if verbose
        end
      end
      Rails.logger.info "Appending #{user.login} to current_cluster, which is size #{current_cluster.size}" if verbose
      current_cluster << user
    end
    clusters << current_cluster if current_cluster.size > 0
    clusters
  end

  # Cluster Users into groups by the temporal proximity of their
  # creation times (or other specified attribute; see below).
  #
  # u      = Array of Users (typically sharing the same last_ip address)
  # params = Optional Hash of params, which may include:
  #   :attr    = Attribute to use for comparison. Defaults to :created_at.
  #   :gap     = Max value to use as the cluster gap. Defaults to the
  #              number of seconds in 72.hours.
  #   :verbose = Produce output during operation (for console use).
  #              Defaults to false.
  #
  # Returns an Array of Arrays of User objects, grouped by the
  # interval between their created_at data.
  def fast_build_clusters(u, params = nil)
    params ||= {}
    cluster_gap = params[:gap] || 72.hours
    cluster_attr = params[:attr] || :created_at
    verbose = params[:verbose]

    intervals = []
    clusters = []
    current_cluster = []

    u.each do |user|
      if last_user = current_cluster.last
        Rails.logger.info "First #{last_user.id}: #{last_user.send(cluster_attr)} \tSecond #{user.id}: #{user.send(cluster_attr)}" if verbose
        # Store the interval between this and the last's creation
        this_interval = user.send(cluster_attr) - last_user.send(cluster_attr)
        intervals << this_interval
        Rails.logger.info "Interval is #{this_interval}, which is #{this_interval > cluster_gap ? 'greater than' : 'less than or equal to'} #{cluster_gap}" if verbose
        if this_interval > cluster_gap
          Rails.logger.info "Interval is above gap. Adding." if verbose
          Rails.logger.info "Clusters before: #{clusters.size} and current_cluster size: #{current_cluster.size}" if verbose
          clusters << current_cluster.dup
          current_cluster = []
          Rails.logger.info "Clusters after: #{clusters.size} and current_cluster size: #{current_cluster.size}" if verbose
        end
      end
      Rails.logger.info "Appending #{user.login} to current_cluster, which is size #{current_cluster.size}" if verbose
      current_cluster << user
    end
    clusters << current_cluster if current_cluster.size > 0
    clusters
  end

  # Find the cluster to which this User belongs.
  #
  # user     = User
  # clusters = Optional Array of Arrays of Users (clusters).
  #            If clusters is not included, it builds a cluster of
  #            Users sharing the #last_ip of 'user'.
  #
  # Returns the Array (cluster) of Users that contains this User,
  # if there is one, or nil otherwise.
  def find_cluster_for(user, clusters = nil)
    # If the user has no last_ip, and we weren't given any clusters
    # to search through, we have no way to build any clusters, so
    # the user is a Cluster of One.
    return [user] unless user.last_ip.present?

    if user.created_at >= 72.hours.ago
      # We don't need every cluster, only recent ones and only at least 3 users.
      # This assumes that this user was created within the last 3 days.
      recent_users_on_ip = User.by_ip(user.last_ip).order(id: :DESC).limit(10).to_a.reverse
      clusters ||= fast_build_clusters(recent_users_on_ip.union([user]))
    end
    clusters ||= build_clusters(User.by_ip(user.last_ip))

    return [user] if clusters.empty?

    clusters.find { |c| c.include? user }
  end

  # Minimum size of a cluster that allows us to reasonably infer spamminess
  # of a new member of the cluster.
  MIN_SPAMMY_CLUSTER_SIZE = 3

  # Check Users in the cluster to see if it's a suspicious-looking group
  # of hoodlums hanging around down on the corner.
  #
  # cluster - Array of Users
  #
  # Returns true if suspicious, false otherwise.
  def cluster_is_suspicious?(cluster)
    return false if cluster.nil?
    cluster_size = cluster.count
    # can't be suspicious below minimum cluster size
    return false if cluster_size < MIN_SPAMMY_CLUSTER_SIZE

    spammy_count = cluster.count { |u| u.spammy }

    # Suspicious if all but one of them are spammy
    return true if spammy_count >= (cluster_size - 1)

    # Nothing to see here, move along.
    false
  end

  # tell the chatterbox room what we find
  CLUSTER_NOTIFICATIONS = "enable_spam_cluster_notifications"

  # Returns `true` if notifications of spam clusters are enabled.
  # Returns `false` if they are disabled.
  #
  def cluster_notifications_enabled?
    "enabled" == Spam::Kv.store.get(CLUSTER_NOTIFICATIONS).value!
  end

  # Set the key in Redis to enable cluster notifications.
  def enable_cluster_notifications
    Spam::Kv.store.set(CLUSTER_NOTIFICATIONS, "enabled")
  end

  # Set the key in Redis to disable cluster notifications.
  def disable_cluster_notifications
    Spam::Kv.store.set(CLUSTER_NOTIFICATIONS, "disabled")
  end
end
