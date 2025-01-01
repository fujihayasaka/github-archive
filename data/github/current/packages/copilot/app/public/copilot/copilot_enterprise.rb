# typed: strict
# frozen_string_literal: true

module Copilot
  class CopilotEnterprise
    extend T::Helpers
    include GitHub::Memoizer
    include Copilot::Metrics

    # TODO: Use Billing::SalesServePlanSubscription::GHEC_FOR_COPILOT_CHARGE_ID when https://github.com/github/github/pull/272911 is merged
    GHEC_FOR_COPILOT_CHARGE_ID = "8a129e0687fb43700187fd9a3efb233d"
    DEFAULT_PAGE_SIZE = 30

    sig { returns(T.nilable(String)) }
    attr_reader :azure_subscription

    sig { returns(::Business) }
    attr_reader :business

    sig { returns(Integer) }
    attr_reader :business_user_count

    sig { returns(Integer) }
    attr_reader :commit_count

    sig { returns(Integer) }
    attr_reader :copilot_seat_count

    sig { returns(Integer) }
    attr_reader :issue_count

    sig { returns(Integer) }
    attr_reader :organization_count

    sig { returns(Integer) }
    attr_reader :pull_request_count

    sig { returns(Integer) }
    attr_reader :repository_count

    sig { returns(String) }
    attr_reader :slug

    sig { params(copilot_business: Copilot::Business).void }
    def initialize(copilot_business)
      @copilot_business   = T.let(copilot_business, Copilot::Business)
      @business           = T.let(@copilot_business.business_object, ::Business)

      @azure_subscription = T.let(@business.customer&.azure_subscription_id, T.nilable(String))
      @slug               = T.let(@business.slug, String)

      # Setting these to blank to make Sorbet happy - at least as close to happy as Sorbet can get
      @business_user_count = T.let(0, Integer)
      @commit_count        = T.let(0, Integer)
      @copilot_seat_count  = T.let(0, Integer)
      @issue_count         = T.let(0, Integer)
      @organization_count  = T.let(0, Integer)
      @pull_request_count  = T.let(0, Integer)
      @repository_count    = T.let(0, Integer)

      # we need to get the organizations for this business first
      organizations    = @business.organizations
      organization_ids = organizations.pluck(:id)

      # let's get their repositories
      repositories = Repository.where(organization_id: organization_ids)

      # find out how many commits they've had across all repositories
      @commit_count = repositories.sum do |repo|
        repo.refs.count
      end

      # find out how many copilot seats they have
      @copilot_seat_count  = Copilot::Seat.where(organization: organizations.to_a).count
      @business_user_count = @business.user_accounts.count

      # find out how many issues they have across all repositories
      @issue_count        = repositories.sum do |repo|
        repo.issues.count
      end

      # find out how many organizations they have created
      @organization_count = organization_ids.count

      # find out how many pull requests they have across all repositories
      @pull_request_count = repositories.sum do |repo|
        repo.pull_requests.count
      end

      # find out how many repositories they have
      @repository_count   = repositories.count
    end

    sig { params(page: Integer, per_page: Integer).returns(T::Array[Copilot::CopilotEnterprise]) }
    def self.sdlc_details(page: 1, per_page: DEFAULT_PAGE_SIZE)
      # because of the deploy freeze (aka "winter is coming"), the billing team implemented this property
      # (`copilot_only?`) as a Zuora rate plan charge id string match.
      #
      # you know, every developer's favorite thing: magic strings
      #
      # _                        _
      # | |__  _   _ __________ _| |__
      # | '_ \| | | |_  /_  / _` | '_ \
      # | | | | |_| |/ / / / (_| | | | |
      # |_| |_|\__,_/___/___\__,_|_| |_|
      #
      # If the business has a CUSTOMER record with a Zuora rate plan charge with the id `8a129e0687fb43700187fd9a3efb233d`,
      # they are Copilot only.
      # load up customer ids with that charge id
      customer_ids = ::Billing::SalesServePlanSubscription.where(
        "zuora_rate_plan_charges LIKE '%#{GHEC_FOR_COPILOT_CHARGE_ID}%'"
      ).pluck(:customer_id)

      # load up the businesses with those customer ids
      businesses = ::Business.where(customer_id: customer_ids).order(slug: :asc)

      # Once migrations are allowed, the billing team is adding in a new column to the businesses table
      # and we'll have to update this
      #
      # ::Business.where(copilot_only: true).paginate(page: page, per_page: per_page)
      #
      # TODO: Remove this after https://github.com/github/github/pull/273126 is merged - it's gross
      WillPaginate::Collection.create(page, per_page, businesses.count) do |pager|
        # we handle the pagination in here because we need to convert these into CopilotEnterprise objects
        paginated_businesses = businesses.paginate(page: page, per_page: per_page)

        results = paginated_businesses.map do |business|
          CopilotEnterprise.new(Copilot::Business.new(business))
        end.to_a

        pager.replace(results)
      end
    end
  end
end
