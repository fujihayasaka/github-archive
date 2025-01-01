# typed: true
# frozen_string_literal: true

class CompromisedCredentialsService
  BATCH_SIZE = 5_000

  # Process a batch of compromised credentials from any data source
  #
  # credentials: - An array of [username, password] pairs
  # datasource_name: - The name of the datasource (e.g., "qintel", "compromised_creds")
  # version: - The version identifier for this batch
  #
  # Returns nothing
  def self.process_credentials_batch(credentials:, datasource_name:, version:)
    return if credentials.empty?

    ActiveRecord::Base.connected_to(role: :writing) do
      CompromisedPasswordDatasource.store_passwords(
        name: datasource_name,
        version: version,
        sha1_passwords: each_password_digest(credentials)
      )

      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: credentials,
        name: datasource_name,
        version: version,
      )
    end
  end

  # Mark a datasource as finished importing
  #
  # datasource_name: - The name of the datasource
  # version: - The version identifier
  #
  # Returns nothing
  def self.mark_import_finished(datasource_name:, version:)
    ActiveRecord::Base.connected_to(role: :writing) do
      datasource = CompromisedPasswordDatasource.find_by(
        name: datasource_name,
        version: version,
        import_finished_at: nil
      )
      datasource.mark_import_as_finished! if datasource
    end
  end

  # Check if a version has already been imported
  #
  # datasource_name: - The name of the datasource
  # version: - The version identifier
  #
  # Returns true if already imported, false otherwise
  def self.already_imported?(datasource_name:, version:)
    CompromisedPasswordDatasource.
      where(name: datasource_name, version: version).
      where.not(import_finished_at: nil).
      exists?
  end

  def self.each_password_digest(credentials)
    unless block_given?
      return enum_for(:each_password_digest, credentials)
    end

    credentials.each do |_username, password|
      next if password.blank?
      yield Digest::SHA1.hexdigest(password) # rubocop:disable GitHub/InsecureHashAlgorithm
    end
  end

  private_class_method :each_password_digest
end
