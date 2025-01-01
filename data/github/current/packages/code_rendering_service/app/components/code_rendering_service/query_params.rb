# typed: strict
# frozen_string_literal: true

module CodeRenderingService # rubocop:disable ViewComponent/ComponentsHaveUnitTests
  module QueryParams
    extend T::Helpers

    requires_ancestor { ApplicationComponent }

    sig { params(repo: T.any(Repository, Gist)).returns(T::Boolean) }
    def bypass_fastly?(repo)
      FeatureFlag.vexi.enabled?(:notebooks_bypass_fastly, repo, default: true) && !GitHub.enterprise?
    end

    sig { returns(ColorMode) }
    def color_mode
      current_user&.color_mode_with_default || ColorMode.default
    end

    sig { returns(T::Boolean) }
    def link_underlines_enabled?
      # prefill associations for user_settings_record so the value can be read safely
      GitHub::PrefillAssociations.prefill_associations([current_user], :user_settings_record)
      current_user&.settings&.get(:link_underlines) || false
    end

    sig { returns(T::Boolean) }
    def logged_in?
      current_user != nil
    end

    sig { returns(T::Hash[Symbol, String]) }
    def useragent_to_h
      T.bind(self, BaseComponent)
      return {} unless opts.has_key?(:parsed_useragent)
      parsed_useragent = opts.fetch(:parsed_useragent)

      {
        browser: parsed_useragent.id.to_s,
        version: parsed_useragent.version,
        platform: parsed_useragent.platform.id.to_s,
        device: parsed_useragent.device.id.to_s
      }
    end
  end
end
