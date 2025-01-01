# typed: true
# frozen_string_literal: true

class SamlProviderSettingsValidator < ActiveModel::Validator
  def validate(record)
    validate_sso_url(record)
    validate_idp_certificate(record)
    if tester = record.try(:user_that_must_test_settings)
      validate_changed_settings_are_tested_by(tester, record)
    end
  end

  private

  def validate_sso_url(record)
    uri = Platform::Scalars::URI.coerce_isolated_input(record.sso_url)
    unless uri.present? && uri.host.present? && %w(http https).include?(uri.scheme)
      record.errors.add(:sso_url, "must be a valid URL")
    end
  end

  def validate_idp_certificate(record)
    cert = Platform::Scalars::X509Certificate.coerce_isolated_input(record.idp_certificate)
    unless cert.present?
      record.errors.add(:idp_certificate, "must be a valid X509 formatted certificate")
    end
  end

  def validate_changed_settings_are_tested_by(tester, record)
    changed_settings = record.changes_to_save
                             .slice(:sso_url, :issuer, :idp_certificate)
                             .select { |_, v| v.first&.squish != v.second&.squish }
                             .keys
    return if changed_settings.none?

    unless record.successfully_tested_by?(tester)
      changed_settings.each do |attr|
        record.errors.add(attr, "new configurations must be tested before saving")
      end
    end
  end
end
