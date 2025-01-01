# typed: true
# frozen_string_literal: true

module GitHub::Pages::Management
  class DeletePathFromHostsDisk

    attr_reader :hosts, :path, :delegate
    DELETE_TIMEOUT = 180 # seconds

    def initialize(hosts:, path:, delegate:)
      @hosts = hosts
      @path = path
      @delegate = delegate
    end

    def perform

      # skip the path other than pages_dir
      return unless path.start_with?(GitHub.pages_dir)
      hosts.map { |host| delegate.ssh(host, "[ -d #{path} ] && rm -rf #{path}", timeout: DELETE_TIMEOUT) }.all?
    end
  end
end
