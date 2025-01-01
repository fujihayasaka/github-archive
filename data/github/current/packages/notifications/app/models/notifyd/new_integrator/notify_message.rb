# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator
  class NotifyMessage
    extend T::Sig
    include Serializable

    sig { params(event: Event).void }
    def initialize(event:)
      @event = event
      @topics = T.let([], T::Array[Entities::Topic])
      @attributes = T.let([], T::Array[Entities::Attribute])

      @subject = @event.subject
      @actor = @event.actor

      yield self if block_given?
    end

    sig { params(notification_type: NotificationType::IType).void }
    def notification_type=(notification_type)
      @notification_type = notification_type
    end

    sig { params(authzd_attributes: T::Array[T::Hash[Symbol, String]]).void }
    def authzd_attributes=(authzd_attributes)
      @authorization = Entities::Authorization.new(owner: @owner, authzd_attributes: authzd_attributes)
    end

    sig { params(id: Integer).void }
    def user_owner_id=(id)
      @owner = Entities::Owner.new_user(id: id)
    end

    sig { params(id: Integer).void }
    def organization_owner_id=(id)
      @owner = Entities::Owner.new_organization(id: id)
    end

    sig { params(owner: Entities::Owner).void }
    def owner=(owner)
      @owner = owner
    end

    sig { params(trigger: String).void }
    def trigger=(trigger)
      @trigger = trigger
    end

    sig { params(repository_id: Integer).void }
    def repository_id=(repository_id)
      @repository_id = repository_id
    end

    sig { params(mobile_layout: T.untyped).void }
    def mobile_layout=(mobile_layout)
      @mobile_layout = mobile_layout
    end

    sig { params(email_layout: T.untyped).void }
    def email_layout=(email_layout)
      @email_layout = email_layout
    end

    sig { params(notification_id: String).void }
    def notification_id=(notification_id)
      @notification_id = notification_id
    end

    sig { params(type: String, value: String).void }
    def push_topic(type:, value:)
      @topics.push(Entities::Topic.new(type: type, value: value))
    end

    sig { params(name: String, value: String).void }
    def push_attribute(name:, value:)
      @attributes.push(Entities::Attribute.new(name: name, value: value))
    end

    sig { params(explicit_recipients: T::Array[Entities::ExplicitRecipientsWithReason]).void }
    def explicit_recipients=(explicit_recipients)
      @explicit_recipients = explicit_recipients
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def as_serializable
      {
        actor: {
          id: actor.id
        },
        context: {
          repository_id: repository_id,
          owner_id: owner.id,
          owner_type: owner.to_symbol,
          trigger: trigger,
        },
        authorization: authorization,
        rendering: {
          mobile: @mobile_layout, # TODO: use T.nilable(Serializable)
          email: @email_layout, # TODO: use T.nilable(Serializable)
        },
        tracking: {
          triggered_at: event.triggered_at
        },
        notification_id: notification_id,
        related_topics: topics,
        attributes: attributes.sort_by { |attribute| attribute.name },
        subject: subject,
        explicit_recipients: explicit_recipients,
        config: notification_type.config,
        # NOTE: There is a typo in our Protobuf definition, so for the moment we need keep it
        feature_swiches: notification_type.feature_switches,
      }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      Serializer.serialize(self)
    end

    private

    sig { returns(Entities::Actor) }
    def actor
      T.let(@actor, Entities::Actor)
    end

    sig { returns(T.nilable(Integer)) }
    def repository_id
      T.let(@repository_id, T.nilable(Integer))
    end

    sig { returns(Entities::Owner) }
    def owner
      T.let(@owner, Entities::Owner)
    end

    sig { returns(String) }
    def trigger
      T.let(@trigger, String)
    end

    sig { returns(Entities::Authorization) }
    def authorization
      T.let(@authorization, Entities::Authorization)
    end

    sig { returns(Event) }
    def event
      T.let(@event, Event)
    end

    sig { returns(String) }
    def notification_id
      T.let(@notification_id, String)
    end

    sig { returns(T::Array[Entities::Topic]) }
    def topics
      T.let(@topics, T::Array[Entities::Topic])
    end

    sig { returns(T::Array[Entities::Attribute]) }
    def attributes
      T.let(@attributes, T::Array[Entities::Attribute])
    end

    sig { returns(Entities::Subject) }
    def subject
      T.let(@subject, Entities::Subject)
    end

    sig { returns(T::Array[Entities::ExplicitRecipientsWithReason]) }
    def explicit_recipients
      T.let(@explicit_recipients, T::Array[Entities::ExplicitRecipientsWithReason])
    end

    sig { returns(NotificationType::IType) }
    def notification_type
      T.let(@notification_type, NotificationType::IType)
    end
  end
end
