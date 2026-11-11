# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class CodingAgentModel
    VENDOR_ICONS = T.let({
      "anthropic" => "/static/images/modules/marketplace/models/families/anthropic.svg",
      "openai" => "/static/images/modules/marketplace/models/families/openai.svg",
    }.freeze, T::Hash[String, String])

    DEFAULT_ICON = T.let("/static/images/icons/copilot/cp-logo.svg", String)

    sig { returns(String) }
    attr_reader :id

    sig { returns(String) }
    attr_reader :name

    sig { returns(T.nilable(String)) }
    attr_reader :description

    sig { returns(T.nilable(String)) }
    attr_reader :vendor

    sig { returns(T.nilable(Float)) }
    attr_reader :multiplier

    sig { params(id: String, name: String, description: T.nilable(String), vendor: T.nilable(String), multiplier: T.nilable(Float)).void }
    def initialize(id:, name:, description: nil, vendor: nil, multiplier: nil)
      @id = T.let(id, String)
      @name = T.let(name, String)
      @description = T.let(description, T.nilable(String))
      @vendor = T.let(vendor, T.nilable(String))
      @multiplier = T.let(multiplier, T.nilable(Float))
    end

    sig { returns(String) }
    def icon
      return DEFAULT_ICON if vendor.nil? || id == "auto"
      VENDOR_ICONS.fetch(T.must(vendor).downcase, DEFAULT_ICON)
    end

    sig do
      params(
        user: User,
        token: T.nilable(T.any(Copilot::DecryptedToken, Copilot::EncryptedToken)),
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
      ).returns(T::Array[CodingAgentModel])
    end
    def self.for_user(user:, token: nil, use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false)
      path = "#{SweAgentPath.base_path(use_staging:, use_staging_jedi_knight:, use_staging_sith_lord:)}/models"
      response = CopilotAPI.make_request(
        token: token,
        integration_id: CopilotAPI::COPILOT_SWE_AGENT,
        user_id: user.id,
        real_ip: nil,
        method: :get,
        path: path
      )

      models_data = if response.is_a?(ConcurrentFaraday::FutureResponse)
        response.value.fetch("data", [])
      else
        response.fetch("data", [])
      end

      from_response(models_data)
    rescue CopilotAPI::Error => e
      Rails.logger.warn("[CodingAgentModel] Failed to fetch coding agent models: #{e.message}")
      []
    end

    sig { params(models_data: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[CodingAgentModel]) }
    def self.from_response(models_data)
      models_data.map do |model|
        new(
          id: model["id"] || model["name"],
          name: model["name"] || model["id"],
          description: model["description"],
          vendor: model["vendor"],
          multiplier: model["billing"]&.dig("multiplier")&.to_f
        )
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        id: id,
        name: name,
        description: description,
        vendor: vendor,
        icon: icon,
        multiplier: multiplier
      }.compact
    end
  end
end
