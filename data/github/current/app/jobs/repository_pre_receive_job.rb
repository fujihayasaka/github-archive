# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Enqueued immediately after a custom pre-receive hook fails.
# All refs pushed are provided in the payload as is the command line output.
#
#   path      - The full path to the repository that was pushed to on disk.
#   pusher    - The String name of the user who performed the push, either
#               directly or via a repository deploy key that they verified.
#   refs      - An Array of [ref, before, after] tuples, one for each
#               ref that was pushed.
#   proto     - The protocol used to push to the repository. Either 'ssh',
#               'http', 'mirror', 'wiki', or 'merge-button'.
#   warning   - Warning printed to the pusher, empty if none
#   error     - Error printed to the pusher, empty if none
#   real_ip   - IP of the pusher.
#
class RepositoryPreReceiveJob < ApplicationJob
  queue_as :repository_pre_receive

  include Instrumentation::Model

  attr_reader :path, :pusher, :refs, :proto, :environment_id, :checksum, :hook_id, :warning, :error, :real_ip

  # Do the dirt.
  def perform(path, pusher, refs, proto, environment_id, checksum, hook_id, warning, error, real_ip = nil)
    @path   = path
    @pusher = pusher
    @refs   = refs
    @proto  = proto
    @environment_id = environment_id
    @checksum = checksum
    @hook_id  = hook_id
    @warning = warning
    @error = error
    @real_ip = real_ip

    Failbot.push(
      job: self.class.name,
      repo: repository&.readonly_name_with_owner,
      user: repository.try(:owner).try(:login),
      refs: refs.inspect,
      pusher: pusher,
      warning: warning,
      error: error,
      pre_receive_environment: environment,
      pre_receive_environment_checksum: checksum,
      pre_receive_hook: hook,
      wiki: wiki?,
    )

    fail "repository doesn't exist" if repository.nil?
    if error.empty?
      instrument(:warned_push, instrumentation_payload)
    else
      instrument(:rejected_push, instrumentation_payload)
    end
  end

  # Returns the Repository object associated with the push.
  def repository
    @repository ||= Repository.with_path(path)
  end

  def actor
    @actor ||= User.find_by_login(pusher)
  end

  def hook
    @hook ||= PreReceiveHook.find_by(id: hook_id)
  end

  def environment
    @environment ||= PreReceiveEnvironment.find_by(id: environment_id)
  end

  # Determine if the push was to a Wiki repository.
  def wiki?
    path =~ /\.wiki\.git$/
  end

  # The logical repository name. This accounts for Wiki repositories.
  def repo_name
    if wiki?
      repository.name + ".wiki"
    else
      repository.name
    end
  end

  def event_prefix
    :pre_receive_hook
  end

  def instrumentation_payload
    payload = {
      repo: repository,
      actor: actor,
      actor_ip: real_ip,
      proto: proto,
      refs: refs,
      pre_receive_environment_id: environment_id,
      pre_receive_environment_checksum: checksum,
      pre_receive_hook_id: hook_id,
      warning: warning,
      error: error,
    }
    if repository.in_organization?
      payload[:org] = repository.organization
    end
    payload
  end
end
