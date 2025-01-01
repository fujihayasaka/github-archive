# typed: strict
# frozen_string_literal: true

module BillingSettings
  # Controls the rendering of our payment method forms.
  class PaymentMethodFieldsView

    include UrlHelpers

    # Public: Get owner that own this credit card.
    sig { returns(::Billing::Types::Account) }
    attr_reader :owner

    # Public: Get the form builder used by credit card specific fields of this view.
    sig { returns(ActionView::Helpers::FormBuilder) }
    attr_reader :form

    # Initialize a PaymentMethodFieldsView object used to control the rendering of
    # credit card forms. Used by the payment_method/fields partials used in
    # our CC and PayPal forms site-wide.
    #
    # owner    - The User or Organization that owns the CC we're updating.
    # form     - A Rails' FormBuilder object that contains these fields.
    # new_repo - A Boolean indicating whether this form is being rendered on
    #            the new repository page. Defaults to `false`.
    sig { params(owner: ::Billing::Types::Account, form: ActionView::Helpers::FormBuilder).void }
    def initialize(owner, form)
      raise ArgumentError.new("Owner required") unless owner.present?
      raise ArgumentError.new("Form required") unless form.present?

      @owner = owner
      @form = form
    end

    sig { returns(T::Boolean) }
    def has_credit_card?
      owner.has_credit_card?
    end

    sig { returns(T::Boolean) }
    def has_paypal_account?
      owner.has_paypal_account?
    end

    sig { returns(String) }
    def owner_login
      owner = self.owner
      return owner.slug if owner.is_a?(Business)
      owner.display_login
    end

    sig { returns(T::Array[T::Array[String]]) }
    def priority_countries
      priorities = ["United States of America", "China", "Germany", "United Kingdom", "India"]
      priorities.filter_map { |country| countries.find { |i| i[0] == country } }
    end

    sig { returns(T::Array[T::Array[String]]) }
    def countries
      ::TradeControls::Countries.currently_unsanctioned
    end

    sig { params(method: T.any(String, Symbol), options: T::Hash[Symbol, T.untyped]).returns(String) }
    def encrypted_text_field(method, options = {})
      options[:name] = ""

      unless options.delete(:has_card)
        options.merge! \
          "data-encrypted-name" => "billing[credit_card][#{method}]",
          :required => "required"
      end

      form.text_field(method, options)
    end

    sig { returns(T.nilable(String)) }
    def card_type
      if owner.payment_method.present? && owner.payment_method.credit_card?
        owner.payment_method.card_type
      end
    end

    sig { returns(T.nilable(String)) }
    def truncated_credit_card_number
      if owner.payment_method.present? && owner.payment_method.credit_card?
        owner.payment_method.formatted_number
      end
    end

    sig { returns(T.nilable(String)) }
    def expiration_month
      if owner.payment_method.present? && owner.payment_method.credit_card?
        "%02d" % owner.payment_method.expiration_month
      end
    end

    sig { returns(T.nilable(Integer)) }
    def expiration_year
      if owner.payment_method.present? && owner.payment_method.credit_card?
        owner.payment_method.expiration_year
      end
    end

    sig { params(country: String).returns(T.nilable(String)) }
    def selected_country(country)
      if owner.payment_method.present? && country == owner.payment_method.country
        "selected=selected"
      end
    end

    sig { params(profile: T.nilable(AccountScreeningProfile), country_code: String).returns(T.nilable(String)) }
    def selected_profile_country(profile, country_code)
      if profile&.country_code == country_code
        "selected=selected"
      end
    end

    sig { params(profile: T.nilable(AccountScreeningProfile), state: String).returns(T.nilable(String)) }
    def selected_profile_state(profile, state)
      if profile&.region == state
        "selected=selected"
      end
    end

    sig { params(state: String).returns(T.nilable(String)) }
    def selected_state(state)
      if owner.payment_method.present? && state == owner.payment_method.region
        "selected=selected"
      end
    end

    sig { returns(T.nilable(String)) }
    def postal_code
      return unless owner.payment_method.present?
      owner.payment_method.postal_code
    end

    sig { returns(T.nilable(String)) }
    def region
      owner.payment_method&.region
    end

    sig { returns(T::Array[T.untyped]) }
    def expiration_month_options
      months = T.let(("01".."12").to_a, T::Array[T.untyped])
      months.unshift(["MM", "", { disabled: true, selected: true }])
    end

    sig { returns(T::Array[T.untyped]) }
    def expiration_year_options
      (Time.now.year..10.years.from_now.year).inject([]) do |array, year|
        array << [year.to_s[2..4], year]
      end.unshift(["YY", "", { disabled: true, selected: true }])
    end
  end
end
