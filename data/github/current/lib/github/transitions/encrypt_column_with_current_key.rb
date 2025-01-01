# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# Docs: https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-dotcom/column-encryption/plaintext-to-encrypted/#backfilling-unencrypted-data
#
# To encrypt a previously unencrypted column with the current key, implement this abstract transition
# by providing the model class that you want to encrypt the column for. This transition was previously used for all
# models with encrypted columns, but has been adapted to an abstract column for data owners to implement and
# own the transition of their data. See https://github.com/github/prodsec-engineering/blob/main/docs/adrs/002-Data-Ownership-in-Column-Encryption.md
#
# [DEPRECATED] To run this transition using the .transitions chatop:
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
    class EncryptColumnWithCurrentKey < Base

      abstract!

      # only arg that can be passed now is the rollback and rollback_attribute_name
      # move checking for the rollback attribute on the model to the after_initialize method
      sig { override.void }
      def after_initialize
        @rollback_attribute_name = T.let(arguments[:rollback_attribute_name]&.to_sym, T.nilable(Symbol))

        @iterator = Iterators::DatabaseTable.new(model_class: model_class)

        log("#{@rollback_attribute_name ? "Rolling back" : "Backfilling"} encryption with the latest key for: [Model: #{model_class.name}, Table: #{model_class.table_name}, Cluster: #{model_class.cluster_name}]")
        if @rollback_attribute_name.nil?
          raise ArgumentError, "#{model_class.name} is not using column encryption" unless model_class.encrypted_attributes.present?
        else
          if !model_class.column_names.include?(@rollback_attribute_name.to_s)
            raise ArgumentError, "#{model_class.name} does not have the specified attribute name (#{@rollback_attribute_name})"
          end
          model_class.encrypts @rollback_attribute_name
        end
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if dry_run?
          log "Would process batch of #{items.count} items"
          return
        end

        items.keys.each do |item|
          model_item = T.let(model_class.find_by(id: item), T.nilable(ApplicationRecord::Base))
          if model_item.nil?
            log("Skipping deleted record #{item}")
            next
          end

          begin
            write_to(model_class:) do
              if @rollback_attribute_name.present?
                # We should be extra careful here and make sure the attribute exists on the model
                # even though we've already checked this in the after_initialize method, double-checking
                # on the instance of the model level is a good idea because calling `read_attribute`
                # on an attribute that doesn't exist will return nil, and we definitely don't want to
                # overwrite existing attribute values with nil unless we're certain its because the stored
                # encrypted value is nil.
                if !model_item.has_attribute?(@rollback_attribute_name)
                  log("ERROR: Skipping #{model_class.name}##{model_item.id} because it does not have the attribute #{@rollback_attribute_name}")
                  next
                end
                decrypted_attribute = model_item.read_attribute(@rollback_attribute_name)
                ActiveRecord::Encryption.without_encryption do
                  model_item.update_column(@rollback_attribute_name, decrypted_attribute)
                end
              else
                model_item.encrypt
              end
            end
          rescue ActiveRecord::Encryption::Errors::Decryption => e
            # This error is raised when we encounter a column that appears to match the signature
            # of an encrypted column but for some reason failed the `encrypted_attribute?` check.
            # This can occur if encrypted data is moved between tables (transposition) and decryption
            # fails because the derived key didn't match that of the encrypted data.
            #
            # We shouldn't really expect this to ever occur in production, but it's a good idea to
            # to catch these cases just in case.
            log("Possible transposed content, encryption skipped for #{model_class.name}##{model_item.id}")
          end
        end
        log "Processed batch of #{items.count} items"
      end

      sig { abstract.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class; end
    end
  end
end
