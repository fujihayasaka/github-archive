# typed: true
# frozen_string_literal: true

module Api::App::IpDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  # Internal: Check whether the current request is coming from a GitHub-internal IP
  #
  # Returns a Boolean.
  def internal_ip_request?
    return false if GitHub.enterprise?
    [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
      "127.0.0.0/8",
      "::1/128",
      "fe80::/10",
      "fc00::/7",
      "192.30.252.0/22",
    ].each do |cidr|
      range = IPAddr.new(cidr)
      return true if range.include?(remote_ip)
    end
    false
  end

  # Internal: Check whether the current request is coming from a GitHub base IP,
  # which would denote that it's likely originating from a GitHub datacenter.
  #
  # Returns a Boolean.
  def base_ip_request?
    return false if GitHub.enterprise?
    GitHub.base_ips.each do |cidr|
      range = IPAddr.new(cidr)
      return true if range.include?(remote_ip)
    end
    false
  end
end
