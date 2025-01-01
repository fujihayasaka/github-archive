# typed: true
# frozen_string_literal: true

module Rails
  def self.application
    self
  end

  def self.config
    self
  end

  def self.gettext_i18n_rails
    self
  end

  def self.use_for_active_record_attributes=(value)
    @use_for_active_record_attributes = value
  end
end
