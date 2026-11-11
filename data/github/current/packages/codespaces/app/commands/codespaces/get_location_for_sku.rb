# typed: strict
# frozen_string_literal: true

module Codespaces
  # Encapsulates business logic to cross check SKU-availability with VSCS locations.
  # Currently several locations do not support GPU skus so we have to redirect their GPU sku traffic to nearby locations.
  class GetLocationForSKU < Command

    sig { returns(String) }
    attr_reader :location, :sku_name

    sig { returns(Symbol) }
    attr_reader :vscs_target

    sig { returns(::User) }
    attr_reader :user

    sig { params(location: String, sku_name: String, vscs_target: Symbol, user: ::User).void }
    def initialize(location:, sku_name:, vscs_target:, user:)
      @location = location
      @sku_name = sku_name
      @vscs_target = vscs_target
      @user = user
    end

    sig { override.returns(String) }
    def perform
      sku = Codespaces::Skus.sku_by_name(sku_name)
      # Currently, we only have one hard rule: some regions don't have GPU skus. In the future, we may want to
      # dynamically determine which regions have SKU availablity
      return location if !sku.gpu?
      return location if supports_gpus?(location)

      gpu_fallback_location = gpu_enabled_fallback(location)
      gpu_stamp = Codespaces::VscsServiceStamp.find(region: gpu_fallback_location, vscs_target:)
      if gpu_stamp.available?(user:)
        gpu_stamp.region.id
      else
        backup_stamp = gpu_stamp.backup(user:)
        if backup_stamp && supports_gpus?(backup_stamp.region.id)
          backup_stamp.region.id
        else
          raise Codespaces::Locations::Region::UnavailableError.new("The assigned location is currently unavailable. Please use a non-GPU machine type or try again later.")
        end
      end
    end

    private

    GPU_LOCATION_FALLBACKS = T.let({
      Codespaces::Locations::Region.find("UkSouth") => Codespaces::Locations::Region.find("WestEurope"),
      Codespaces::Locations::Region.find("CentralIndia") => Codespaces::Locations::Region.find("SouthEastAsia"),
      Codespaces::Locations::Region.find("AustraliaCentral") => Codespaces::Locations::Region.find("AustraliaEast"),
    }, T::Hash[Codespaces::Locations::Region, Codespaces::Locations::Region])

    sig { params(location: String).returns(T::Boolean) }
    def supports_gpus?(location)
      !GPU_LOCATION_FALLBACKS.include?(Codespaces::Locations::Region.find(location))
    end

    sig { params(location: String).returns(String) }
    def gpu_enabled_fallback(location)
      return location if supports_gpus?(location)

      GPU_LOCATION_FALLBACKS.fetch(Codespaces::Locations::Region.find(location)).id
    end
  end
end
