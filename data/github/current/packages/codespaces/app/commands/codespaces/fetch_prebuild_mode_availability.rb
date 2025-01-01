# typed: true
# frozen_string_literal: true

module Codespaces
  class FetchPrebuildModeAvailability < Command
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

    # This class is used to fetch the prebuild mode (whether prebuilds are enabled, and if so, what kind)
    # for a given sku in a given repository+branch+prebuild hash combination and cache the result
    # for the lifetime of the object.

    include ActiveModel::Validations
    include ActiveModel::Validations::Callbacks

    validates_presence_of :repository
    validates_presence_of :branch_name, message: "could not be set from ref_name"
    validates_presence_of :oid, message: "must be present or able to be inferred from ref_name"
    validates_presence_of :vscs_target
    validates_presence_of :location
    validates :location, inclusion: { in: :valid_locations, message: "%{value} is not a valid location" }
    validates_presence_of :ref, message: "could not be found"

    validate :ref_is_a_branch

    before_validation :set_default_branch_name
    before_validation :set_default_oid
    def initialize(repository:, location:, codespace_owner:, ref_name: nil, oid: nil, vscs_target: nil, vscs_target_url: nil, devcontainer_path: nil)
      @repository = repository
      @location = location
      @vscs_target = vscs_target&.to_sym || Codespaces::Vscs.default_target
      @vscs_target_url = vscs_target_url
      @ref_name = ref_name
      @oid = oid
      @devcontainer_path = devcontainer_path
      @codespace_owner = codespace_owner
    end

    # returns a hash of skus and their available prebuild modes
    # Example: { xLargePremiumLinux: "ready" }
    def perform
      with_database_error_fallback do
        validate!

        return nil unless Codespaces::Prebuilds.configured?(repository)

        @prebuild_skus ||= begin
          @request_failed = nil
          vscs_response = fetch_available_skus_for_prebuild!

          sku_available_modes = {}
          vscs_response.fetch("supportedSkus", []).each do |sku|
            sku_available_modes[sku] = Prebuilds::AvailabilityStatus::IN_PROGRESS
          end
          vscs_response.fetch("templateSkus", []).each do |sku|
            sku_available_modes[sku] = Prebuilds::AvailabilityStatus::READY
          end

          sku_available_modes.symbolize_keys
        rescue Codespaces::Client::BadResponseError, Faraday::TimeoutError, Faraday::ConnectionFailed => e
          record_error(e)
          @request_failed = true
          return nil
        end
      end
    end

    private

    attr_reader :repository, :branch_name, :oid, :location, :vscs_target, :vscs_target_url, :devcontainer_path, :codespace_owner

    memoize def ref
      @ref_name.present? ? repository&.refs&.find(@ref_name) : repository&.refs&.find(repository&.default_branch)
    end

    def record_error(error)
      Failbot.report(
        error,
        "catalog_service" => "github/codespaces",
        "gh.repo.id" => repository.id,
        "gh.codespaces.vscs_target" => vscs_target,
      )
    end

    def request_failed?
      @request_failed == true
    end

    def fetch_available_skus_for_prebuild!
      client.fetch_prebuild_available_skus!(
        repo: repository,
        branch_name: branch_name,
        prebuild_hash: prebuild_hash,
        devcontainer_path: devcontainer_path,
        fast_path_enabled: fast_path_enabled_for_configuration,
        codespace_owner: codespace_owner,
      )
    end

    def prebuild_hash
      @prebuild_hash ||= Codespaces::CalculatePrebuildHash.call(repository: repository, oid: oid, devcontainer_path: devcontainer_path)
    end

    def client
      @client ||= Codespaces::VscsClient.for_prebuild(location: location, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
    end

    def fast_path_enabled_for_configuration
      configuration = Codespaces::PrebuildConfiguration.find_by(repository_id: repository.id, branch: branch_name, devcontainer_path: devcontainer_path, vscs_target: vscs_target)
      if !configuration.present? && vscs_target == Codespaces::Vscs.default_target
        configuration = Codespaces::PrebuildConfiguration.find_by(repository_id: repository.id, branch: branch_name, devcontainer_path: devcontainer_path, vscs_target: nil)
      end

      configuration&.fast_path_enabled || false
    end

    # ==== Validations ====

    def ref_is_a_branch
      errors.add(:ref, "must be a branch") unless ref&.branch?
    end

    def valid_locations
      Codespaces::Locations::Region.where(vscs_target:).map(&:id)
    end

    # ==== Callbacks ====

    def set_default_oid
      return if @oid.present?
      @oid = ref&.target_oid
    end

    def set_default_branch_name
      return if @branch_name.present?
      @branch_name = ref&.name if ref&.branch?
    end
  end
end
