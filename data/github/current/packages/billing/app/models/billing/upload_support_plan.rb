# typed: strict
# frozen_string_literal: true


module Billing
  # Public: A Plain Old Ruby Object (PORO) used for uploading a support plan.

  class UploadSupportPlan
    extend T::Sig

    # inputs - Hash containing attributes to create a support plan
    # inputs[:accounts_file] - The CSV file containing the accounts to update.
    sig { params(accounts_file: T.untyped, dry_run: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
    def self.call(accounts_file:, dry_run: false)
      new(accounts_file: accounts_file, dry_run: dry_run).call
    end

    sig { params(accounts_file: T.untyped, dry_run: T::Boolean).void }
    def initialize(accounts_file:, dry_run: false)
      @accounts_file = accounts_file
      @dry_run = dry_run
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def call
      if @accounts_file.blank?
        return { success: false, message: "No file selected" }
      end

      result = SupportPlanUploader.new(accounts_file: @accounts_file, dry_run: @dry_run).perform

      if result[:count_of_accounts_updated] > 0 && result[:business_ids_not_found].length > 0
        {
          success: true,
          message: "Support plans updated for #{result[:count_of_accounts_updated]} accounts. Businesses ID's couldn't be found for: #{result[:business_ids_not_found].first(10)} (Only showing first 10).",
          updates: result[:updates]
        }
      elsif result[:count_of_accounts_updated] > 0
        { success: true, message: "Support plans updated for #{result[:count_of_accounts_updated]} accounts.", updates: result[:updates] }
      else
        { success: false, message: "Couldn't succesfully update any accounts. #{result[:business_ids_not_found].count} businesses not found." }
      end
    end
  end
end
