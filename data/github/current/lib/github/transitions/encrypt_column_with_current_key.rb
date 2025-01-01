# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# Docs: https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-dotcom/column-encryption/plaintext-to-encrypted/#backfilling-unencrypted-data
#
# To run this transition using the .transitions chatop:
#  1. Append the date and reason for running this transition at the bottom of this comment block
#  2. Open a PR with the changes and have it reviewed by the transitions-reviewers team
#  3. Once the PR is approved, run the transition in the #dotcom-transitions-ops slack channel like so:
#    ```
#     .transitions run <pull-request-url> <environment-or-*> encrypt_column_with_current_key.rb --write --model <model-name>
#    ```
#  4. Check the logs (#dotcom-transitions-logs) and datadog dashboard to ensure the transition ran as expected
#
# [DEPRECATED] To run this transition directly (using gh-screen):
#    ```
#     $ cd /data/github/current
#     # First, run the transition in dry-run mode
#     $ gudo bin/safe-ruby lib/github/transitions/encrypt_column_with_current_key.rb --verbose -m Particle | tee -a /tmp/encrypt_previously_unencrypted_column.log
#     # Then, run the transition in regular mode
#     $ gudo bin/safe-ruby lib/github/transitions/encrypt_column_with_current_key.rb --verbose -m Particle -w | tee -a /tmp/encrypt_previously_unencrypted_column.log
#    ```
#
# More info about running transitions: https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/
#
# Usage History (approximate dates):
#  ????-??-??: Prior usage has not been tracked here
#  2024-01-08: Run on dotcom production after rotating column encryption keys due to SEC-6209 (https://github.com/github/security-6209-urgent-remediation)
#
module GitHub
  module Transitions
    class EncryptColumnWithCurrentKey < Transition

      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100

      ENCRYPTED_MODELS = [
        TwoFactorCredential,
        SmsRegistration,
        TotpAppRegistration,
        Business::SamlProviderTestSettings,
        Business::SamlProvider,
        TeamSync::Tenant,
        TeamSync::BusinessTenant,
        ExternalIdentityRefreshToken,
        User,
        SponsorsPatreonCampaignWebhook,
        SponsorsPatreonUser,
        IntegrationAgent,
        HookConfigAttribute,
      ]

      def after_initialize
        if other_args[:model].present? && other_args[:all].present?
          raise ArgumentError, "Please specify either a model or the --all option, but not both"
        end

        @rollback = other_args[:rollback_attribute_name].present?
        @rollback_attribute_name = other_args[:rollback_attribute_name]&.to_sym
        if @rollback && !other_args[:model].present?
          raise ArgumentError, "Must use --model when specifying --rollback_attribute_name"
        end

        @klasses = if other_args[:model]
          model = Object.const_get(other_args[:model])

          if !@rollback
            raise ArgumentError, "#{other_args[:model]} is not using column encryption" unless model.encrypted_attributes.present?
          end

          [model]
        elsif other_args[:all]
          ENCRYPTED_MODELS
        else
          raise ArgumentError, "You must specify a model to encrypt OR --all to encrypt all models"
        end

        if @klasses.empty?
          raise RuntimeError, "There are no models using encrypted attributes... aborting"
        end
      end

      def perform
        log("#{@rollback ? "Rolling back" : "Backfilling"} encryption with the latest key for: [#{@klasses.map(&:name).join(', ')}]")
        @klasses.each do |klass|

          if @rollback
            if !klass.column_names.include?(@rollback_attribute_name.to_s)
              raise RuntimeError, "Class #{klass.name} does not have the specified attribute name (#{@rollback_attribute_name})"
            end
            klass.encrypts @rollback_attribute_name
          end

          table_literal = GitHub::SQL::LITERAL(klass.table_name)
          min_id = readonly { klass.github_sql.value("SELECT COALESCE(MIN(id), 0) FROM :table", table: table_literal) }
          max_id = readonly { klass.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM :table", table: table_literal) }
          count = 0

          log("#{klass.name}: Beginning column encryption backfill for #{klass.name}")

          readonly do
            klass.in_batches(of: BATCH_SIZE, start: min_id, finish: max_id) do |batch|
              klass.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
                log("#{klass.name}: Processing batch ##{count += 1}")
                process(batch) unless dry_run?
              end
            end
          end

          log("#{klass.name}: Finished processing #{count} batches with #{BATCH_SIZE} rows per batch")
        end
        log("Finished column encryption backfill")
      end

      def process(batch)
        ActiveRecord::Base.connected_to(role: :writing) do
          batch.each do |obj|
            begin
              if @rollback
                decrypted_attribute = decrypt(obj)
                ActiveRecord::Encryption.without_encryption do
                  obj.update_attribute(@rollback_attribute_name, decrypted_attribute)
                end
              else
                obj.encrypt
              end
            rescue ActiveRecord::Encryption::Errors::Decryption => e
              # This error is raised when we encounter a column that appears to match the signature
              # of an encrypted column but for some reason failed the `encrypted_attribute?` check.
              # This can occur if encrypted data is moved between tables (transposition) and decryption
              # fails because the derived key didn't match that of the encrypted data.
              #
              # We shouldn't really expect this to ever occur in production, but it's a good idea to
              # to catch these cases just in case.
              log("Possible transposed content, encryption skipped for #{obj.class.name}##{obj.id}")
            end
          end
        end
      end

      def decrypt(obj)
        type = obj.type_for_attribute(@rollback_attribute_name)
        encrypted_value = obj.ciphertext_for(@rollback_attribute_name)
        type.deserialize(encrypted_value)
      end
    end
  end
end


# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: encrypt_column_with_current_key.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("-mMODEL", "--model=MODEL", "Name of the model you wish to perform encryption on") do |model|
      options[:model] = model
    end

    opts.on("-a", "--all", "Run the transition on all models") do
      options[:all] = true
    end

    opts.on("-rATTRIBUTE", "--rollback_attribute_name=ATTRIBUTE", "Name of the attribute you wish to roll back. Only used with --model") do |attribute|
      options[:rollback_attribute_name] = attribute
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::EncryptColumnWithCurrentKey.new(**options)
  transition.run
end
