# typed: true
# frozen_string_literal: true

module Api::Serializer::ElmExporterSecretsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  def elm_exporter_org_secret_hash(data, options = {})
    secret = data[:secret]
    return nil unless secret

    updated_at = secret.updated_at
    created_at = secret.created_at

    if updated_at.nil?
      updated_at = created_at
    end

    {
      name: secret.name,
      created_at: time(Time.at(created_at.seconds).utc.to_datetime),
      updated_at: time(Time.at(updated_at.seconds).utc.to_datetime),
    }
  end
end
