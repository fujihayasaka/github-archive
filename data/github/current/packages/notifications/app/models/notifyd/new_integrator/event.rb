# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator
  class Event
    Map = T.type_alias { T::Hash[Symbol, T.untyped] }

    extend T::Sig

    sig { returns(Entities::Subject) }
    attr_reader :subject

    sig { returns(Entities::Actor) }
    attr_reader :actor

    sig { returns(Time) }
    attr_reader :triggered_at

    sig { params(hash: Map).returns(T.attached_class) }
    def self.from_h(hash)
      new(
        subject: Entities::Subject.from_h(T.let(hash[:subject], Map)),
        actor: Entities::Actor.from_h(T.let(hash[:actor], Map)),
        builder: T.let(hash[:builder], MessageBuilder),
        triggered_at: T.let(hash[:triggered_at], T.nilable(Time)),
      )
    end

    sig do
      params(subject: Entities::Subject, actor: Entities::Actor, builder: MessageBuilder, triggered_at: T.nilable(Time)).void
    end
    def initialize(subject:, actor:, builder:, triggered_at: nil)
      @subject = subject
      @actor = actor
      @builder = builder
      @triggered_at = triggered_at || Time.now
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        subject: @subject.to_h,
        actor: @actor.to_h,
        builder: @builder,
        triggered_at: @triggered_at
      }
    end

    sig { returns(T.nilable(NotifyMessage)) }
    def to_message
      @builder.build_message(event: self)
    end
  end
end
