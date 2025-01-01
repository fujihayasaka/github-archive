# typed: true
# frozen_string_literal: true

module Site::Localization
  class Config
    def initialize(actor: nil, request: nil)
      @actor = actor
      @request = request
    end

    def for_actor(actor)
      self.class.new(actor: actor, request: @request)
    end

    def for_request(request)
      self.class.new(actor: @actor, request: request)
    end

    def available_locales
      %w[
        en
        ja
        ko
        pt
        es
      ]
    end

    def default_locale
      available_locales.first
    end

    def allowed_accept_language_headers
      %w[en-US ja pt-BR ko-KR es-419]
    end

    # Delete once product localization files removed (:internationalization service owner has been removed)
    def ugc_inline_machine_translation_enabled?
      FeatureFlag.vexi.enabled?(:ugc_inline_machine_translation, @actor, default: false)
    end
  end
end
