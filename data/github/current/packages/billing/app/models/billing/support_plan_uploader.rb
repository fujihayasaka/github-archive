# typed: strict
# frozen_string_literal: true

module Billing
  class SupportPlanUploader

    HeaderError = Class.new(StandardError)
    MAX_THROTTLE_RETRIES = 5

    sig { params(accounts_file: T.untyped, dry_run: T::Boolean).void }
    def initialize(accounts_file:, dry_run: false)
      @accounts_file = accounts_file
      @plans_not_found = T.let(Set.new, T::Set[String])
      @updates = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      @business_ids_not_found = T.let([], T::Array[Integer])
      @dry_run = dry_run
    end

    sig do
      returns({
        updates: T::Array[T::Hash[Symbol, T.untyped]],
        count_of_accounts_updated: Integer,
        business_ids_not_found: T::Array[Integer],
        plans_not_found: T::Set[String]
      })
    end
    def perform
      accounts = T.let(accounts_from_csv(accounts_file: @accounts_file), T::Array[T::Hash[Symbol, T.untyped]])

      accounts.each do |account|
        Business.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          process(account)
        end
      end
      {
        updates: @updates,
        count_of_accounts_updated: @updates.count,
        business_ids_not_found: @business_ids_not_found,
        plans_not_found: @plans_not_found
      }
    end

    sig { params(account: T::Hash[Symbol, T.untyped]).void }
    def process(account)
      id = account[:id]
      business = Business.find_by(id: id)

      if business
        plan = account[:support_plan]&.downcase
        from = business.microsoft_support_plan
        if business.update_microsoft_support_plan(plan, dry_run: @dry_run)
          @updates << { id: id, slug: business.display_login, from: from, to: plan }
        else
          @plans_not_found << plan
        end
      else
        @business_ids_not_found << id
      end
    end

    sig { params(accounts_file: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def accounts_from_csv(accounts_file:)
      file = CSV.read accounts_file,
        headers: true,
        header_converters: :symbol,
        converters: :all
      required_headers = [:id, :support_plan]
      required_headers.each do |header|
        unless T.unsafe(file).headers.include?(header)
          raise HeaderError.new("Required header #{header} is missing")
        end
      end
      file.map { |row| T.cast(row, CSV::Row).to_hash }
    end
  end
end
