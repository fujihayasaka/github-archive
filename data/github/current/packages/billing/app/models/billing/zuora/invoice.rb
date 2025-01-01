# typed: true
# frozen_string_literal: true

# For a full list of fields available in the Zuora Invoice object, see:
# https://www.zuora.com/developer/api-references/api/operation/Get_GetInvoice/
module Billing
  module Zuora
    class Invoice
      include GitHub::Memoizer
      include Scientist

      CANCELLED = "Canceled"
      POSTED = "Posted"
      # Zuora only allows up to 200 conditions in a ZOQL query's WHERE clause.
      # See https://knowledgecenter.zuora.com/Central_Platform/Query/ZOQL#Limits
      ZOQL_QUERY_WHERE_CLAUSE_LIMIT = 200

      sig { params(account_id: String).returns(T::Array[Billing::Zuora::Invoice]) }
      def self.past_due(account_id:)
        response = GitHub.zuorest_client.query_action queryString: "select Id from Invoice where AccountId = '#{account_id}' and Status = 'Posted' and DueDate < #{GitHub::Billing.today} and Balance > 0"

        response["records"].map { |record| new(record["Id"]) }
      end

      sig { params(zuora_account_id: String, posted_only: T::Boolean).returns(T::Array[Billing::Zuora::Invoice]) }
      def self.open_invoices_for_account(zuora_account_id, posted_only: false)
        return [] if zuora_account_id.blank?

        query = "select Id from Invoice where AccountId = '#{zuora_account_id}' and Balance > 0"
        query += " and Status = 'Posted'" if posted_only
        response = GitHub.zuorest_client.query_action queryString: query

        response["records"].map { |record| new(record["Id"]) }
      end

      sig { params(zuora_subscription_number: String).returns(T::Array[Billing::Zuora::Invoice]) }
      def self.invoices_for_subscription(zuora_subscription_number)
        return [] if zuora_subscription_number.blank?

        response = GitHub.zuorest_client.query_action queryString: "select InvoiceId from InvoiceItem where SubscriptionNumber = '#{zuora_subscription_number}'"

        create_raw_invoices_from_zuora(response)
      end

      # zuora_transaction_id: The ID of the Zuora Payment
      sig { params(zuora_transaction_id: String, billable_entity: T.nilable(Billing::Types::Account)).returns(T::Array[Billing::Zuora::Invoice]) }
      def self.invoices_for_transaction(zuora_transaction_id, billable_entity: nil)
        response = GitHub.zuorest_client.query_action queryString: "select InvoiceID from InvoicePayment where PaymentId = '#{zuora_transaction_id}'"

        create_raw_invoices_from_zuora(response, billable_entity: billable_entity)
      end

      sig { params(zuora_account_id: String).returns(T::Array[Billing::Zuora::Invoice]) }
      def self.invoices_for_account(zuora_account_id)
        if GitHub.flipper[:billing_invoices_for_account_optimization].enabled?
          fields = %w(Id InvoiceNumber Amount InvoiceDate DueDate Balance)
          query = "select #{fields.join(",")} from Invoice where AccountId = '#{zuora_account_id}' and Status = 'Posted' and SuppressFromCustomerView__c = 'No'"
          response = GitHub.zuorest_client.query_action queryString: query

          response["records"].map do |record|
            record.merge!({
              "AccountId" => zuora_account_id,
              "SuppressFromCustomerView__c" => "No",
              "Status" => "Posted"
            })
            new(record["Id"], record)
          end
        else
          invoices = Zuorest::Model::Account.new(id: zuora_account_id).invoices
          invoices.map { |record| new(record["id"], record) }
        end
      rescue Zuorest::Error
        []
      end

      # Public: Record metrics based on an invoice balance and the callsite
      #
      # balance_in_cents - invoice balance in USD cents, an Integer
      # calling_class - String name of the class where the metrics are being recorded from
      #
      sig { params(balance_in_cents: T.nilable(Numeric), calling_class: String).void }
      def self.record_metrics(balance_in_cents:, calling_class:)
        return unless balance_in_cents.is_a?(Numeric)

        tags = ["class:#{calling_class}"]

        if balance_in_cents.negative?
          tags << "balance:negative"
        elsif balance_in_cents.zero?
          tags << "balance:zero"
        else
          tags << "balance:positive"
        end

        if balance_in_cents.negative?
          GitHub.dogstats.count("zuora.invoices.balance_in_cents",
                                balance_in_cents.abs,
                                tags: tags,
                               )
        end
        GitHub.dogstats.increment("zuora.invoices", tags: tags)
      end

      # Private: take the response from zuora and create invoices
      #
      # Returns an array of ::Billing::Zuora::Invoice records
      def self.create_raw_invoices_from_zuora(response, billable_entity: nil)
        response
          .fetch("records", [])
          .uniq { |invoice| invoice["InvoiceId"] }
          .compact
          .map { |record| new(record["InvoiceId"], billable_entity: billable_entity) }
      end
      private_class_method :create_raw_invoices_from_zuora

      # Public: The GitHub::Retraint::Lock key to obtain before making changes to the invoice
      sig { params(invoice_id: String).returns(String) }
      def self.lock_key(invoice_id)
        "zero-out-zuora-invoice-#{invoice_id}"
      end

      sig do
        params(
          invoice_id: String,
          raw_invoice: T.nilable(T.any(Hash, Zuorest::Model::Invoice)),
          billable_entity: T.nilable(Billing::Types::Account)
        ).void
      end
      def initialize(invoice_id, raw_invoice = nil, billable_entity: nil)
        Failbot.push("gh.billing.zuora_invoice.id" => invoice_id)

        @invoice_id = invoice_id
        @_raw_invoice = raw_invoice
        @billable_entity = billable_entity
      end

      attr_reader :invoice_id

      sig { returns(String) }
      def id
        raw_invoice["id"] || raw_invoice["Id"]
      end

      sig { returns(String) }
      def invoice_number
        raw_invoice["invoiceNumber"] || raw_invoice["InvoiceNumber"]
      end
      alias_method :number, :invoice_number

      sig { returns(String) }
      def account_id
        raw_invoice["accountId"] || raw_invoice["AccountId"]
      end

      sig { returns(T.nilable(String)) }
      memoize def subscription_number_from_billable_line_items
        # We use this query to avoid pulling all invoice items (which has lead to timeouts in the past)
        query = "select SubscriptionNumber from InvoiceItem where InvoiceId = '#{id}' and ChargeAmount > 0"
        response = GitHub.zuorest_client.query_action queryString: query
        return if response["records"].empty?

        response["records"].first["SubscriptionNumber"]
      end

      sig { returns(Numeric) }
      def amount
        raw_invoice["amount"] || raw_invoice["Amount"]
      end

      sig { returns(Numeric) }
      def refund_amount
        raw_invoice["refundAmount"] || raw_invoice["RefundAmount"]
      end

      sig { returns(Numeric) }
      def tax_amount
        raw_invoice["taxAmount"] || raw_invoice["TaxAmount"]
      end

      # The date the invoice was created in YYYY-MM-DD format
      sig { returns(String) }
      def invoice_date
        raw_invoice["invoiceDate"] || raw_invoice["InvoiceDate"]
      end

      # The date the invoice is due in YYYY-MM-DD format
      sig { returns(String) }
      def due_date
        raw_invoice["dueDate"] || raw_invoice["DueDate"]
      end
      alias_method :due_on, :due_date

      sig { returns(String) }
      def status
        raw_invoice["status"] || raw_invoice["Status"]
      end

      sig { returns(String) }
      def suppress_from_customer_view
        raw_invoice["SuppressFromCustomerView__c"] || "No"
      end

      sig { returns(T::Boolean) }
      def suppress_from_customer_view?
        suppress_from_customer_view == "Yes"
      end

      # The amount applied to this invoice via a Payment
      sig { returns(::Billing::Types::Numeric) }
      def payment_amount
        raw_invoice["paymentAmount"] || raw_invoice["PaymentAmount"]
      end

      # The amount applied to this invoice via a CreditBalanceAdjustment
      sig { returns(::Billing::Types::Numeric) }
      def credit_balance_adjustment_amount
        raw_invoice["creditBalanceAdjustmentAmount"] || raw_invoice["CreditBalanceAdjustmentAmount"]
      end

      sig { returns(::Billing::Types::Numeric) }
      def balance
        raw_invoice["balance"] || raw_invoice["Balance"]
      end

      # Base64 encoded PDF of the invoice
      # https://knowledgecenter.zuora.com/Zuora_Central_Platform/API/G_SOAP_API/E1_SOAP_API_Object_Reference/Invoice/Query_an_Invoice_Body_Field
      sig { returns(String) }
      def body
        if raw_invoice["body"].present?
          raw_invoice["body"]
        else
          body_query = "select Body from Invoice where Id = '#{id}'"
          response = GitHub.zuorest_client.query_action queryString: body_query
          if response["records"].empty?
            return ""
          end

          response["records"].first["Body"].to_s
        end
      end

      # Public: The invoice date in %Y/%m/%d format
      #
      # This is used for display purposes
      sig { returns(String) }
      def formatted_invoice_date
        DateTime.parse(invoice_date).strftime("%Y/%m/%d")
      rescue TypeError, ArgumentError
        "N/A"
      end

      # Public: The payment status of the invoice
      #
      # This is used for display purposes
      sig { returns(String) }
      def payment_status
        if posted?
          if paid?
            "Paid"
          elsif past_due?
            "Payment Overdue"
          else
            "Invoiced"
          end
        else
          status.titleize
        end
      end

      sig { returns(T::Boolean) }
      def cancelled?
        status == CANCELLED
      end

      sig { returns(T::Boolean) }
      def posted?
        status == POSTED
      end

      sig { returns(T::Boolean) }
      def paid?
        balance <= 0
      end

      sig { params(as_of: T.untyped).returns(T::Boolean) }
      def past_due?(as_of: GitHub::Billing.today)
        Date.parse(due_on) < as_of
      end

      sig { returns(T::Boolean) }
      def credit_balance_adjustment_used?
        # An amount was subtracted from an existing credit balance
        credit_balance_adjustment_amount < 0
      end

      sig { returns(T.nilable(String)) }
      def zuora_credit_balance_adjustment_id
        return @zuora_credit_balance_adjustment_id if defined?(@zuora_credit_balance_adjustment_id)

        response = GitHub.zuorest_client.query_action(
          queryString: "select Id from CreditBalanceAdjustment where SourceTransactionId = '#{invoice_id}' and SourceTransactionType = 'Invoice'"
        )
        record = response["records"].first
        @zuora_credit_balance_adjustment_id =
          if record
            record["Id"]
          end
      end

      sig { returns(T::Boolean) }
      def payment_used?
        payment_amount > 0
      end

      # Public: get the list of invoice items for this invoice. If subscribable tracking is
      # enabled, attempt to match the subscription rate plan charge for all items to their
      # subscribable so consumers don't need to look it up by eg. matching on the charge
      # name.
      sig { returns(T::Array[T.any(Billing::Zuora::InvoiceItem, Billing::Zuora::SubscribableInvoiceItem)]) }
      memoize def invoice_items
        if use_resolver?
          Billing::Zuora::SubscribableInvoiceItemResolver.call(invoice_id)
        else
          invoice_items = Billing::Zuora::InvoiceItem.all(invoice_key: invoice_id)
          subscribables = invoiced_subscribables(invoice_items)
          invoice_items.map do |item|
            if subscribable = subscribables[item.rate_plan_charge_id]
              item.as_subscribable_invoice_item(subscribable: subscribable)
            else
              item
            end
          end
        end
      end

      sig { returns(String) }
      def lock_key
        self.class.lock_key(id)
      end

      private

      attr_reader :billable_entity

      # Private: use subscribable tracking to associate rate plan charges with subscribables.
      #
      # Examples
      #
      #   invoiced_subscribables(invoice_items)
      #   # =>  { "1c92..." => #<SponsorsTier id: 42, ...> }
      #
      # Returns Hash of { rate_plan_charge_id => subscribable }
      sig do
        params(
          invoice_items: T::Array[Billing::Zuora::InvoiceItem]
        ).returns(T::Hash[String, ::Billing::Types::Subscribable])
      end
      def invoiced_subscribables(invoice_items)
        @invoiced_subscribables ||=
          begin
            # Get a tracking ID map of { rate_plan_charge_id => tracking_id } and
            # product rate plan charge ID map of { rate_plan_charge_id => product_rpc_id }
            # product_rpc_id will be used to map the invoice item to a marketplace listing plan
            #
            #  tracking_id => {
            #    "1c92..." => "MDEyOlNwb25zb3JzVGllcjEz",
            #    "2c92..." => "MDEyOlNwb25zb3JzVGllcjE0",
            #    "3c92..." => "MDIyOk1hcmtldHBsYWNlTGlzdGluZ1BsYW4x",
            #    "4c92..." => "MDEyOlNwb25zb3JzVGllcjE1",
            #    "5c92..." => nil,
            #    ...
            #  }
            #  product_rpc_id => {
            #    "1c92..." => "c0f9...",
            #    "2c92..." => "d0f9...",
            #    "3c92..." => "e0f9...",
            #    ...
            #  }
            result = tracking_ids(invoice_items)
            # T.must because values are defaulted as empty instead of nil
            tracking_id_map, product_rpc_id_map = T.must(result.first), T.must(result.last)


            # Get a subscribable map of { tracking_id => subscribable }
            #  {
            #    "MDEyOlNwb25zb3JzVGllcjEz"             => #<SponsorsTier id: 42, ...>,
            #    "MDEyOlNwb25zb3JzVGllcjE0"             => #<SponsorsTier id: 43, ...>,
            #    "MDIyOk1hcmtldHBsYWNlTGlzdGluZ1BsYW4x" => #<Marketplace::ListingPlan id: 18, ...>,
            #    "MDEyOlNwb25zb3JzVGllcjE1"             => #<SponsorsTier id: 44, ...>,
            #    ...
            #  }

            tracking_ids_to_lookup = tracking_id_map.values.select(&:present?)
            subscribable_map = Billing::Subscribable.from_tracking_ids(tracking_ids_to_lookup)

            # Get a subscribable map of { product_rpc_id => subscribable }
            #  {
            #    "c0f9..." => #<Marketplace::ListingPlan id: 18, ...>,
            #    ...
            #  }
            product_rpc_ids_to_lookup = product_rpc_id_map.values.select(&:present?)
            product_rpc_subscribable_map = Billing::Subscribable.from_product_rpc_ids(product_rpc_ids_to_lookup)
            # Return a map of { rate_plan_charge_id => subscribable }
            #
            #  {
            #    "1c92..." => #<SponsorsTier id: 42, ...>,
            #    "2c92..." => #<SponsorsTier id: 43, ...>,
            #    "3c92..." => #<Marketplace::ListingPlan id: 18, ...>,
            #    "4c92..." => #<SponsorsTier id: 99, ...>,
            #  }
            rpc_id_subscribable_map = tracking_id_map.inject({}) do |map, (rate_plan_charge_id, tracking_id)|
              map.merge!(rate_plan_charge_id => subscribable_map[tracking_id])
            end

            if product_rpc_subscribable_map
              subscribable_map.merge!(product_rpc_subscribable_map)
              product_rpc_id_map.inject(rpc_id_subscribable_map) do |map, (rate_plan_charge_id, product_rpc_id)|
                map.merge!(rate_plan_charge_id => subscribable_map[product_rpc_id])
              end
            end
            rpc_id_subscribable_map
          end
      end

      # Private: get the Rate Plan Charge Id values from the invoice items, and query those
      # rate plan charges for the subscribable custom field and ProductRatePlanChargeId.
      # ProductRatePlanChargeId is used to map the invoice item to a marketplace listing plan.
      #
      # Examples
      #
      #   tracking_ids(invoice_items)
      #   # =>  [ "tracking_field" => { "1c92..." => "MDEyOlNwb25zb3JzVGllcjEz" },
      #            "product_rpc_id" => { "1c92..." => "c0f9..." }
      #
      # Returns Array of 2 Hashes. tracking_field => { String rate_plan_charge_id => String tracking id } and product_rpc_id => { String rate_plan_charge_id => String product rpc id }
      sig do
        params(
          invoice_items: T::Array[Billing::Zuora::InvoiceItem]
        ).returns(T::Array[T::Hash[String, String]])
      end
      def tracking_ids(invoice_items)
        rpc_ids = invoice_items.map(&:rate_plan_charge_id).compact
        return [{}, {}] if rpc_ids.empty?

        tracking_field = Billing::Subscribable::ZUORA_TRACKING_FIELD

        records = rpc_tracking_data(rpc_ids, tracking_field: tracking_field)
        tracking_id_map = {}
        product_rate_plan_charge_id_map = {}
        records.inject([]) do |_map, record|
          rate_plan_charge_id = record["Id"]
          tracking_id = record[tracking_field]
          tracking_id_map.merge!({ rate_plan_charge_id => tracking_id })
          unless tracking_id.present?
            product_rate_plan_charge_id_map.merge!({ rate_plan_charge_id => record["ProductRatePlanChargeId"] })
          end
        end
        [tracking_id_map, product_rate_plan_charge_id_map]
      end

      def rpc_tracking_data(rpc_ids, tracking_field:)
        rpc_ids.each_slice(ZOQL_QUERY_WHERE_CLAUSE_LIMIT).inject([]) do |records, rpc_ids_slice|
          # ID values come from previous ZOQL query and are assumed safe to interpolate
          where_clause = rpc_ids_slice.map { |id| "Id = '#{id}'" }.join(" OR ")
          query = "SELECT Id, #{tracking_field}, ProductRatePlanChargeId FROM RatePlanCharge WHERE #{where_clause}"
          response = GitHub.zuorest_client.query_action(queryString: query)
          records.concat(response["records"])
        end
      end

      def raw_invoice
        return @_raw_invoice unless @_raw_invoice.nil?

        result = GitHub.zuorest_client.get_invoice(invoice_id)
        if result["success"]
          @_raw_invoice = result
        else
          @_raw_invoice = {}
          Failbot.push("gh.billing.zuora.result" => result)

          raise Billing::Zuora::ResourceNotFoundError.new("Invoice #{invoice_id} not found")
        end
      end

      sig { returns(T::Boolean) }
      def use_resolver?
        billable_entity.present?
      end
    end
  end
end
