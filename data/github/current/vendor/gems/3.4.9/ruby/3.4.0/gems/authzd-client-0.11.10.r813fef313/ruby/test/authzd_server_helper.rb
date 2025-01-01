# frozen_string_literal: true

require "socket"

TEST_HMAC_KEY = "authzdhmac"
TEST_CAPHMAC_KEY = "authzdcaphmac"
TEST_CONTROLACCESS_HMAC_KEY = "controlaccesshmac"
SERVER_ADDR = "127.0.0.1:18082"
TWIRP_ADDR = "http://#{SERVER_ADDR}/twirp/"

DEFAULT_ENV = {
  "HMAC_KEY_0" => TEST_HMAC_KEY,
  "CAPEVALUATOR_HMAC_KEY_0" => TEST_CAPHMAC_KEY,
  "CAPEVALUATOR_SERVICE_ENABLED" => "true",
  "CONTROLACCESS_HMAC_KEY_0" => TEST_CONTROLACCESS_HMAC_KEY,
  "CONTROLACCESS_SERVICE_ENABLED" => "true"
}

def start_server(addr, bin_path: nil, out: "/dev/null", port: "18081")
  return if ENV["SKIP_AUTHZD"]

  @env = DEFAULT_ENV.merge(
    "HTTP_ADDR" => addr,
    "PORT" => port
  )
  bin_path ||= ENV.fetch("AUTHZD_BIN_PATH", "script/server --no-db-resolver")
  @pid = Process.spawn(@env, bin_path, %i[out err] => out)
  await_connection(addr)
end

def stop_server
  return unless @pid

  Process.kill("TERM", @pid)
  Process.wait(@pid)
end

def await_connection(addr, timeout: 30)
  Timeout.timeout(timeout) do
    until listening_service?(addr)
      sleep 1
      puts "Waiting authzd server at #{addr} to listen..."
    end
  end
end

def listening_service?(addr, timeout: 5)
  host, port = addr.split(":", 2)
  Timeout.timeout(timeout) do
    socket = TCPSocket.new(host, port)
    socket&.close
    true
  rescue Errno::ECONNREFUSED
    false
  end
end

def create_enumerator_client(twirp_address: TWIRP_ADDR, hmac_secret: TEST_HMAC_KEY)
  Authzd::Enumerator::Client.new(twirp_address) do |c|
    c.use :for_actor, with: [
      Authzd::Middleware::HmacSignature.new(instrumenter: Debug, key: hmac_secret)
    ]
    c.use :for_subject, with: [
      Authzd::Middleware::HmacSignature.new(instrumenter: Debug, key: hmac_secret)
    ]
  end
end

def for_subject_request(subject_id: 123_456,
                        subject_type: "Repository",
                        actor_type: "User",
                        scope: "all",
                        relationship: "read")
  Authzd::Enumerator::ForSubjectRequest.new(
    subject_id:,
    subject_type:,
    actor_type:,
    options: Authzd::Enumerator::Options.new(relationship:, scope:)
  )
end

def for_actor_request(actor_id: 123_456,
                      actor_type: "User",
                      subject_type: "Repository",
                      scope: "all",
                      relationship: "read")
  Authzd::Enumerator::ForActorRequest.new(
    actor_id:,
    actor_type:,
    subject_type:,
    options: Authzd::Enumerator::Options.new(relationship:, scope:)
  )
end

def create_capevaluator_client(twirp_address: TWIRP_ADDR, hmac_secret: TEST_CAPHMAC_KEY)
  Authzd::CapEvaluator::Client.new(twirp_address) do |c|
    c.use :evaluate_policies_for_single_resource, with: [
      Authzd::Middleware::HmacSignature.new(instrumenter: Debug, key: hmac_secret)
    ]
    c.use :evaluate_policies_for_filtering, with: [
      Authzd::Middleware::HmacSignature.new(instrumenter: Debug, key: hmac_secret)
    ]
  end
end

def evaluate_policies_for_single_resource_request(resource_id: 123_456, resource_type: "NotResolvable", policy_group: "non_real_group_name", policy: nil)
  policy_attr = get_policy_attr(policy_group, policy)

  resource_id_attr = Authzd::Proto::Attribute.wrap("conditional.access.resource.id", resource_id)
  resource_type_attr = Authzd::Proto::Attribute.wrap("conditional.access.resource.type", resource_type)

  Authzd::CapEvaluator::SingleResourceRequest.new(
    attributes: [resource_id_attr, resource_type_attr, policy_attr]
  )
end

def evaluate_policies_for_filtering_request(targets: [], policy_group: "non_real_group_name", policy: nil)
  policy_attr = get_policy_attr(policy_group, policy)

  req_targets = targets.map do |target|
    Authzd::CapEvaluator::Target.new(id: target[:id], type: target[:type], visibilities: [])
  end

  Authzd::CapEvaluator::FilterRequest.new(attributes: [policy_attr], targets: req_targets)
end

def get_policy_attr(policy_group, policy)
  raise ArgumentError, "only one of policy_group or policy can be provided" if policy_group && policy

  if policy_group
    Authzd::Proto::Attribute.wrap("conditional.access.policy_group", policy_group)
  else
    Authzd::Proto::Attribute.wrap("conditional.access.policy", policy)
  end
end

def create_controlaccess_client(twirp_address: TWIRP_ADDR, hmac_secret: TEST_CONTROLACCESS_HMAC_KEY)
  Authzd::ControlAccess::Client.new(twirp_address) do |c|
    c.use :check, with: [
      Authzd::Middleware::HmacSignature.new(instrumenter: Debug, key: hmac_secret)
    ]
  end
end

def make_controlaccess_request
  Authzd::ControlAccess::Request.new
end

class Debug
  def self.instrument(name, payload = {})
    print("time: #{Time.now.strftime('%H:%M:%S.%L')}\nevent: #{name}\npayload: #{payload}\n\n")
    yield payload if block_given?
  end
end
