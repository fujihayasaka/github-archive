# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  class EisPollJob < ApplicationJob

    queue_as :eis_poll
    retry_on_dirty_exit

    schedule interval: 2.minutes, condition: -> { !GitHub.enterprise? }

    CACHE_KEY = "trade_controls:sdn:eis_offset_value"

    sig { void }
    def perform
      processed_messages = 0
      offset = TradeCompliance::Kv.store.get(CACHE_KEY).value! || "0"
      messages_count = 0
      api_call_loops = 10

      while api_call_loops >= 0 && messages_count.zero? # we need to keep polling until we get a message
        begin
          # do the API call and pass the message to parser
          eis_bus_response = ApiService.make_eis_request(offset: offset)

          messages_count = eis_bus_response.messages.count
          api_call_loops -= 1 if messages_count.zero?

          eis_bus_response.messages.each do |message|
            processed_messages += 1 if process_message(message, offset)
          end

          to_datadog("sdn_api_service.eis.batch.count", messages_count, ["offset:#{offset}"])
          to_datadog("sdn_api_service.eis.batch.processed", processed_messages, ["offset:#{offset}"])

          if offset == eis_bus_response.last_offset # we've reached the end of the stream
            to_datadog("sdn_api_service.eis.end_of_stream", 1, ["offset:#{offset}"])
            break
          end

          offset = eis_bus_response.last_offset
          with_write do
            TradeCompliance::Kv.store.set(CACHE_KEY, offset)
          end

          rescue ApiServiceError => e
            Failbot.report(e)
            to_datadog("sdn_api_service.eis.batch.processed", processed_messages, ["offset:#{offset}"])
            return
        end
      end
    end

    private

    # Processes the message from the trade screening response and persists the trade screening status for the account and its contacts, if any.
    # We only count it as a failure if the account screening status fails to save,
    # while we do a best effort to persist the screening status for each contact information belonging to the Billing::Types::Account
    sig { params(message: EisBusResponse::Message, offset: String).returns(T::Boolean) }
    def process_message(message, offset)
      screening_profile = AccountScreeningProfile.find_by(external_uuid: message.external_id)
      return false unless valid_screening_profile?(message: message, screening_profile: screening_profile)

      with_write do
        return false unless persist_account_screening_status(message: message, screening_profile: T.must(screening_profile), offset: offset)
        persist_contact_screening_status(message: message, screening_profile: T.must(screening_profile), offset: offset)
      end

      true
    end

    # Persists the top level trade screening status for the Billing::Types::Account, which is the most restrictive
    # status of all the contact trade screening statuses for the account
    sig { params(message: EisBusResponse::Message, screening_profile: AccountScreeningProfile, offset: String).returns(T::Boolean) }
    def persist_account_screening_status(message:, screening_profile:, offset:)
      status_reason = { "status_reason": message.status_reason }
      screening_profile.msft_trade_screening_status = message.status
      screening_profile.metadata = screening_profile.metadata.merge(status_reason)

      billing_address_response = message.requests.find { |r| r.request_id == screening_profile.request_id }
      screening_profile.billing_trade_screening_status = billing_address_response.status if billing_address_response.present?

      update_successful = screening_profile.save(validate: false)

      if screening_profile.errors.any? || !update_successful
        screening_profile.errors.add(:save, "unsuccessful") unless update_successful
        transaction_error = screening_profile.errors.map do |error|
          "#{error.attribute}:#{error.type}"
        end.join("-")

        Failbot.report(EisBusResponseParsingError.new(transaction_error), external_uuid: message.external_id, status: message.status, offset: offset)
        return false
      end

      instrument_result_to_hydro(message, screening_profile)
      true
    end

    # Persists the trade screening status for the contacts of the Billing::Types::Account. An account can have one or more contact information (billing, shipping, etc)
    sig { params(message: EisBusResponse::Message, screening_profile: AccountScreeningProfile, offset: String).returns(T::Boolean) }
    def persist_contact_screening_status(message:, screening_profile:, offset:)
      responses = message.requests
      request_ids = responses.map(&:request_id)
      screening_profile.owner.customer&.contacts&.each do |contact|
        contact = T.cast(contact, Billing::Contact)
        response = responses.find { |r| r.request_id == contact.trade_screening_request_id }

        if response.nil?
          request_ids << contact.trade_screening_request_id
          next
        end

        request_ids.delete(contact.trade_screening_request_id)
        contact.update(trade_screening_status: response.status)
      end

      if request_ids.any?
        error = "Missing contact request ids: #{request_ids.join(", ")}"
        Failbot.report(EisBusResponseParsingError.new(error), external_uuid: message.external_id, offset: offset)
      end

      request_ids.blank?
    end

    sig { params(message: EisBusResponse::Message, screening_profile: T.nilable(AccountScreeningProfile)).returns(T::Boolean) }
    def valid_screening_profile?(message:, screening_profile:)
      if screening_profile.nil?
        Failbot.report(ActiveRecord::RecordNotFound.new("AccountScreeningProfile not found for external_uuid: #{message.external_id} with received status: #{message.status}"))
        return false
      end

      if screening_profile.owner.nil?
        Failbot.report(UnknownActorError.new("AccountScreeningProfile owner is nil for external ID: #{message.external_id} with received status: #{message.status}"))
        return false
      end

      if !screening_profile.respond_to?("#{message.status}!")
        Failbot.report(EisBusResponseParsingError.new("The given status isn't part of the contract statuses with SDN. external_uuid: #{message.external_id} with received status: #{message.status}"))
        return false
      end

      true
    end

    sig { params(key: String, value: Integer, tags: T::Array[String]).void }
    def to_datadog(key, value, tags)
      GitHub.dogstats.count(
        key,
        value,
        tags: tags
      )
    end

    # Private: Instruments the trade screening response to Hydro for analytics
    sig { params(message: EisBusResponse::Message, upp: AccountScreeningProfile).void }
    def instrument_result_to_hydro(message, upp)
      GlobalInstrumenter.instrument("sdn_trade_screening.result_available", {
        country: upp.country_code,
        external_user_id: message.external_id,
        request_id: message.eid,
        request_type: :EIS,
        status: message.status,
        actor_type: upp.hydro_actor
      })
    end
  end
end
