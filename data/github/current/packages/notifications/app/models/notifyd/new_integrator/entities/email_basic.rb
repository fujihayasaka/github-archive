# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class EmailBasic
    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(String) }
    attr_accessor :subject

    sig { returns(String) }
    attr_accessor :body

    sig { returns(String) }
    attr_accessor :text_body

    sig { returns(String) }
    attr_accessor :url

    sig { returns(String) }
    attr_accessor :to

    sig { returns(T::Hash[String, String]) }
    attr_accessor :reasons_to_words

    sig { returns(T::Hash[String, String]) }
    attr_accessor :headers

    sig { params(block: T.nilable(T.proc.params(arg0: EmailBasic).void)).void }
    def initialize(&block)
      @subject = T.let("", String)
      @body = T.let("", String)
      @text_body = T.let("", String)
      @from = T.let(nil, T.nilable(Notifyd::Proto::Layouts::Email::From))
      @url = T.let("", String)
      @unsubscribe_url_templates = T.let(nil, T.nilable(Notifyd::Proto::Layouts::Email::UnsubscribeUrlTemplates))
      @reasons_to_words = T.let({}, T::Hash[String, String])
      @to = T.let("", String)
      @headers = T.let({}, T::Hash[String, String])

      yield self if block_given?
    end

    sig { params(templates: T::Hash[Symbol, String]).void }
    def unsubscribe_url_templates=(templates)
      @unsubscribe_url_templates = Notifyd::Proto::Layouts::Email::UnsubscribeUrlTemplates.new(templates)
    end

    sig { params(name: T.nilable(String), email: T.nilable(String)).void }
    def use_from(name: nil, email: nil)
      @from = Notifyd::Proto::Layouts::Email::From.new(name: name, email: email)
    end

    sig { override.returns(Notifyd::Proto::Layouts::Email::Basic) }
    def as_serializable
      Notifyd::Proto::Layouts::Email::Basic.new(
        subject: subject,
        body: body,
        text_body: text_body,
        from: @from,
        url: url,
        unsubscribe_url_templates: @unsubscribe_url_templates,
        reasons_to_words: reasons_to_words,
        to: to,
        headers: headers,
      )
    end
  end
end
