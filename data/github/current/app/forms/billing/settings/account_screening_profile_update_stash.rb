# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module AccountScreeningProfileUpdateStash
      class << self
        def stash_update_for(target, params, errors = nil)
          model_errors = (errors || target.trade_screening_record.errors)
            .group_by_attribute
            .each_with_object({}) do |(k, v), memo|
              memo[k] = v.map(&:full_message)
            end

          ::TradeCompliance::Kv.store.set(
            key_for(target),
            { params: params, errors: model_errors }.to_json,
            expires: 5.minutes.from_now
          )
        end

        def retrieve_stashed_update_for(target)
          result = ::TradeCompliance::Kv.store.get(key_for(target))

          if result.ok? && (value = result.value!)
            AccountScreeningProfileUpdateResult.new(JSON.parse(value))
          else
            ValidAccountScreeningProfileUpdateResult.instance
          end
        end

        def delete_stashed_update_for(target)
          ::TradeCompliance::Kv.store.del(key_for(target))
        end

        private

        def key_for(target)
          "account_screening_profile_update/#{target.id}"
        end
      end
    end

    # rubocop:disable Rails/ModuleNaming
    class AccountScreeningProfileUpdateResult
      include GitHub::Memoizer

      def initialize(data)
        @data = data
      end

      def primer_form_attributes_for(field_name)
        field_name = field_name.to_s

        {}.tap do |attributes|
          if errors.include?(field_name)
            attributes[:validation_message] = errors[field_name].first
            attributes[:aria] = { invalid: true }
          end

          if params.include?(field_name)
            attributes[:value] = params[field_name]
          end
        end
      end

      def field_value(field_name)
        params[field_name]
      end

      def valid?
        errors.none?
      end

      private

      memoize def errors
        @data["errors"]
      end

      memoize def params
        @data["params"]
      end
    end

    class ValidAccountScreeningProfileUpdateResult
      include Singleton

      def primer_form_attributes_for(*)
        {}
      end

      def field_value(*)
        nil
      end

      def valid?
        true
      end
    end
    # rubocop:enable Rails/ModuleNaming
  end
end
