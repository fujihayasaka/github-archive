# typed: false
# frozen_string_literal: true

# Public: methods for parsing and representing data from a repository's push audit_log.
class LoggedPush
  attr_writer :user_login, :name, :pusher, :via
  attr_accessor :time, :targets, :received_objects, :receive_pack_size,
                 :non_fast_forward, :merge_button,
                :ssh_connection, :user_agent, :real_ip, :remote_ip,
                :frontend_ssh_connection, :pubkey_fingerprint,
                :pubkey_verifier_login, :pull_request_id, :server,
                :user_id, :pubkey_verifier_id, :ssh_ca_id, :ssh_ca_owner_type,
                :ssh_ca_owner_id

  KEYS = Set.new([:time, :targets, :received_objects, :receive_pack_size, :pusher,
                :user_login, :name, :non_fast_forward, :merge_button,
                :ssh_connection, :user_agent, :real_ip, :remote_ip,
                :frontend_ssh_connection, :pubkey_fingerprint,
                :pubkey_verifier_login, :pull_request_id, :via, :server,
                :user_id, :pubkey_verifier_id, :ssh_ca_id, :ssh_ca_owner_type,
                :ssh_ca_owner_id])

  AnonNames = Set.new(%w(git anonymous))

  def initialize(time = nil, targets = nil, received_objects = nil,
                 receive_pack_size = nil, pusher = nil, user_login = nil,
                 name = nil, non_fast_forward = nil, merge_button = nil,
                 ssh_connection = nil, user_agent = nil, real_ip = nil,
                 remote_ip = nil, frontend_ssh_connection = nil,
                 pubkey_fingerprint = nil, pubkey_verifier_login = nil,
                 pull_request_id = nil, via = nil, server = nil, user_id = nil,
                 pubkey_verifier_id = nil, ssh_ca_id = nil,
                 ssh_ca_owner_type = nil, ssh_ca_owner_id = nil)
    @time = time,
    @targets = targets,
    @received_objects = received_objects,
    @receive_pack_size = receive_pack_size,
    @pusher = pusher,
    @user_login = user_login,
    @name = name,
    @non_fast_forward = non_fast_forward,
    @merge_button = merge_button,
    @ssh_connection = ssh_connection,
    @user_agent = user_agent,
    @real_ip = real_ip,
    @remote_ip = remote_ip,
    @frontend_ssh_connection = frontend_ssh_connection,
    @pubkey_fingerprint = pubkey_fingerprint,
    @pubkey_verifier_login = pubkey_verifier_login,
    @pull_request_id = pull_request_id,
    @via = via,
    @server = server,
    @user_id = user_id,
    @pubkey_verifier_id = pubkey_verifier_id
    @ssh_ca_id = ssh_ca_id
    @ssh_ca_owner_type = ssh_ca_owner_type
    @ssh_ca_owner_id = ssh_ca_owner_id
  end

  def self.keys
    KEYS
  end

  def self.parse_reflog_line(line)
    ref, before, after, rest = line.split(" ", 4)
    hash = nil
    if rest =~ /^(.*?) (<.*>) (\d+) ([0-9+-]+)(.*)$/
      name, email, timestamp, offset, json = $1, $2, $3.to_i, $4, $5 || ""
      name = name.force_encoding(Encoding::UTF_8).scrub!
      time = Time.at(timestamp)

      target = LoggedPushTarget.new(ref, before, after)
      hash = { name: name, targets: [target], time: time }

      if json =~ /\A\s*\{/
        hash.merge!(GitHub::JSON.parse(json).symbolize_keys)
      end
    end
    hash ? from(hash) : nil
  end

  def self.preload_associations(pushes)
    user_ids = []
    pull_ids = []

    pushes.compact!

    pushes.each do |push|
      user_ids << (push.user_id || push.pubkey_verifier_id)
      pull_ids << push.pull_request_id if push.pull_request_id
    end

    pull_ids.compact!
    pull_ids.uniq!

    user_ids.compact!
    user_ids.uniq!

    users = User.where(id: user_ids).index_by(&:id)
    pulls = PullRequest.where(id: pull_ids).index_by(&:id)

    pushes.each do |push|
      push.user = users[push.user_id]
      push.deploy_key_verifier = users[push.pubkey_verifier_id]
      push.pull_request = pulls[push.pull_request_id]
    end
  end

  def self.from(hash)
    push = new

    hash.each do |key, value|
      next unless keys.include?(key)
      push.send(:"#{key}=", value)
    end

    push
  end

  # Convert this LoggedPush into a Hash containing its data
  #
  # Returns a Hash
  def to_hash
    KEYS.each_with_object({}) do |key, hash|
      hash[key] = instance_variable_get("@#{key}")
    end
  end

  # Add a target to this LoggedPush.
  #
  # line - the String line of output from git-push-log with an
  #        additional target ref/before/after.
  #
  # Used when multiple refs are pushed in the same operation.
  #
  # Returns the LoggedPush.
  def add_target(line)
    targets << LoggedPushTarget.parse_reflog_line(line)
  end

  # Public: whether multiple refs were pushed in this operation.
  #
  # Returns a Boolean.
  def multiple_refs?
    targets.size > 1
  end

  # Public: Get the number of refs pushed in this operation.
  #
  # Returns the Integer ref count.
  def ref_count
    targets.size
  end

  # Public: Get the LoggedPushTarget if only one ref was pushed in this operation.
  #
  # Returns the LoggedPushTarget that was pushed, or nil if multiple refs were pushed.
  def target
    targets.first unless multiple_refs?
  end

  alias objects received_objects
  alias pack_size receive_pack_size
  alias pubkey pubkey_fingerprint
  attr_writer :pull_request, :user, :deploy_key_verifier

  # Get the PullRequest associated with this push. Normally set by
  # preload_associations.
  #
  # Uses #find_by_id to prevent ActiveRecord::RecordNotFound if the
  # PR doesn't exist.
  #
  # Returns a PullRequest or nil if there is no PR for this push.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def pull_request
    @pull_request ||= begin
      id = pull_request_id.to_i
      PullRequest.find_by_id(id) if id > 0
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Get the User that performed this push, for cases where user
  # credentials were used to authenticate. Normally set by
  # preload_associations.
  #
  # Use #find_by_id to prevent ActiveRecord::RecordNotFound if the
  # user doesn't exist.
  #
  # Returns a User or nil if user credentials were not used to push.
  def user
    @user ||= if user_id
      User.find_by_id(user_id)
    elsif @pusher
      User.find_by_login(@pusher)
    end
  end

  # Get the User that verified the deploy key that performed this
  # push. Normally set by preload_associations.
  #
  # Use #find_by_id to prevent ActiveRecord::RecordNotFound if the
  # user doesn't exist.
  #
  # Returns a User or nil if a deploy key was not used for this push.
  def deploy_key_verifier
    @deploy_key_verifier ||= User.find_by_id(pubkey_verifier_id) if pubkey_verifier_id
  end

  def user_login
    @user_login_object ||= (@user_login || pusher).to_s
  end

  def pusher
    @pusher_object ||= @pusher || name
  end

  def name
    n = @name
    AnonNames.include?(n) ? nil : n
  end

  def type
    non_fast_forward ? :force_push : :push
  end

  def commit_range
    "#{before}...#{after}"
  end

  def short_commit_range
    "#{before.to_s[0, 7]}...#{after.to_s[0, 7]}"
  end

  def human_type
    @human_type ||= type.to_s.gsub("_", " ")
  end

  def merged?
    !!merge_button
  end

  # Check whether this push was performed using a deploy key.
  #
  # A deploy_key_verifier should only be present when a :pubkey_verifier_id
  # is present in the corresponding push-log entry. This indicates that the
  # push was authenticated using a deploy key rather than user credentials.
  #
  # Returns a Boolean.
  def deploy_key?
    !!deploy_key_verifier
  end

  def proto
    if ssh_connection
      :ssh
    elsif user_agent
      :http
    end
  end

  def human_proto
    @human_proto ||= proto.to_s.gsub("_", " ")
  end

  def ip
    @ip ||= (real_ip || remote_ip || frontend_ssh_connection).to_s.split.first
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def via
    @via_object ||= @via || ("merge button" if merge_button)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def ssh_cert?
    !ssh_ca_id.nil? && !ssh_ca_owner_type.nil? && !ssh_ca_owner_id.nil?
  end

  def ssh_ca
    return nil unless ssh_cert?
    return @ssh_ca if defined?(@ssh_ca)

    @ssh_ca = SshCertificateAuthority.find_by_id(ssh_ca_id)
  end

  def ssh_ca_owner
    return nil unless ssh_cert?
    return @ssh_ca_owner if defined?(@ssh_ca_owner)

    @ssh_ca_owner = case ssh_ca_owner_type
    when ::Organization.base_class.name
      ::Organization.find_by_id(ssh_ca_owner_id)
    when ::Business.name
      ::Business.find_by_id(ssh_ca_owner_id)
    end
  end

  def ssh_ca_owner_description
    return nil unless ssh_cert?

    case ssh_ca_owner
    when ::Organization
      "type=organization id=#{ssh_ca_owner.id} login=#{ssh_ca_owner.login}"
    when ::Business
      "type=enterprise id=#{ssh_ca_owner.id} slug=#{ssh_ca_owner.slug}"
    else
      case ssh_ca_owner_type
      when ::Organization.base_class.name
        "type=organization id=#{ssh_ca_owner_id}"
      when ::Business.name
        "type=enterprise id=#{ssh_ca_owner_id}"
      end
    end
  end

  def ssh_ca_description
    return nil unless ssh_cert?

    if ssh_ca
      "id=#{ssh_ca.id} fpr=#{ssh_ca.base64_fingerprint}"
    else
      "id=#{ssh_ca_id}"
    end
  end

  def ssh_cert_description
    return nil unless ssh_cert?

    "a SSH certificate"
  end

  def using
    @using ||= user_agent || pubkey || ssh_cert_description
  end
end
