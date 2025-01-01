# typed: true
# frozen_string_literal: true

module Codespaces
  class CreatePrebuildInstance < Command

    class Error < Codespaces::Error; end
    class InvalidTarget < Error; end

    attr_accessor :repository,
                  :pool_code,
                  :location,
                  :vscs_target,
                  :vscs_target_url,
                  :environment_options,
                  :branch
    attr_reader :entry_point

    def initialize(
        repository:,
        pool_code:,
        location:,
        vscs_target: Codespaces::Vscs.default_target,
        vscs_target_url: nil,
        environment_options: {},
        branch: nil,
        entry_point: nil
    )
      @repository = repository
      @pool_code = pool_code
      @location = location
      @vscs_target = vscs_target.to_sym
      @vscs_target_url = vscs_target_url
      @environment_options = environment_options
      @branch = branch
      @entry_point = entry_point
    end

    def perform
      validate!

      client.create_prebuild_instance(
        pool_code: pool_code,
        location: location,
        github_token: github_token,
        secrets: secrets,
        environment_options: environment_options,
        repository: repository,
      )
    rescue Codespaces::Client::TimeoutError => e
      raise Codespaces::Client::TimeoutError.new(e)
    end

    private

    def validate!
      Codespaces::ValidatePrebuildAccess.call(repository: repository, vscs_target: nil, vscs_target_url: vscs_target_url)
      if vscs_target_url.present? && (vscs_target.blank? || vscs_target != :local)
        raise InvalidTarget, "vscs_target must be 'local' to specify a devstamp URL"
      end
    end

    def client
      return @client if defined?(@client)
      @client = Codespaces::VscsClient.for_prebuild(
        location: location,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url
      )
    end

    def secrets_data
      return @secrets_data if defined?(@secrets_data)
      @secrets_data = Codespaces::GetPrebuildSecrets.call(repository: repository, pat_secret_required: true, branch: branch, entry_point: entry_point)
    end

    def secrets
      secrets_data[:secrets]
    end

    def github_token
      secrets_data[:github_token]
    end
  end
end
