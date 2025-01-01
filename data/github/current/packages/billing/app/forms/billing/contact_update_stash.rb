# typed: strict
# frozen_string_literal: true

class Billing::ContactUpdateStash
  include GitHub::Memoizer

  class << self
    sig { returns(T.attached_class) }
    def empty
      new({})
    end

    sig do
      params(
        target: Billing::Types::Account,
        address_type: String,
        params: ActionController::Parameters,
        errors: T.nilable(ActiveModel::Errors)
      ).void
    end
    def stash_update_for(target, address_type, params, errors = nil)
      model_errors = (errors || model_errors_for(target, address_type))
        .group_by_attribute
        .each_with_object({}) do |(k, v), memo|
          memo[k] = v.map(&:full_message)
        end

      ::Billing::Kv.store.set(
        key_for(target, address_type),
        { params: params, errors: model_errors }.to_json,
        expires: 5.minutes.from_now
      )
    end

    sig { params(target: T.nilable(Billing::Types::Account), address_type: String).returns(Billing::ContactUpdateStash) }
    def retrieve_stashed_update_for(target, address_type)
      return self.empty if target.nil?
      result = ::Billing::Kv.store.get(key_for(target, address_type))

      if result.ok? && (value = result.value!)
        self.new(JSON.parse(value))
      else
        self.empty
      end
    end

    sig { params(target: Billing::Types::Account, address_type: String).void }
    def delete_stashed_update_for(target, address_type)
      return if target.nil?
      ::Billing::Kv.store.del(key_for(target, address_type))
    end

    private

    sig { params(target: Billing::Types::Account, address_type: String).returns(ActiveModel::Errors) }
    def model_errors_for(target, address_type)
      return target.shipping_contact.errors if address_type == "shipping"
      target.billing_contact.errors
    end

    sig { params(target: Billing::Types::Account, address_type: String).returns(String) }
    def key_for(target, address_type)
      "#{address_type}_information_update/#{target.id}"
    end
  end

  # Instance methods

  sig { params(data: T::Hash[T.any(String, Symbol), T.untyped]).void }
  def initialize(data)
    @data = T.let(data.with_indifferent_access, T::Hash[T.any(String, Symbol), T.untyped])
  end

  sig { params(field_name: T.any(String, Symbol)).returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  def primer_form_attributes_for(field_name)
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

  sig { params(field_name: T.any(String, Symbol)).returns(T.nilable(String)) }
  def field_value(field_name)
    params[field_name]
  end

  sig { returns(T::Boolean) }
  def errors?
    !errors.none?
  end

  private

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  attr_reader :data

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  memoize def errors
    data.fetch("errors", {})
  end

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  memoize def params
    data.fetch("params", {})
  end
end
