# typed: true
# frozen_string_literal: true

require_relative "../../packages/localization/app/public/localization"
require_relative "../../packages/localization/app/public/localization/config"

require "fast_gettext"
require "gettext_i18n_rails"

config = Localization::Config.new

# that messes up AR validation messages
Rails.application.config.gettext_i18n_rails.use_for_active_record_attributes = false

FastGettext.add_text_domain "github", path: File.join(Rails.root, "config/locales"), type: :po
FastGettext.default_text_domain = "github"
FastGettext.default_available_locales = config.available_locales

contact_sales_languages = %w[de fr ja]
I18n.available_locales = config.available_locales + contact_sales_languages
FastGettext.default_locale = config.default_locale.to_sym

# this allow devs to check missing translations.That can be handy in test or development environments
Localization.raise_on_missing_translations = (ENV["I18N_RAISE_ON_MISSING_TRANSLATIONS"] == "1")
