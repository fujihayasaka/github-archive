# typed: true
# frozen_string_literal: true

# This class wraps Notifyd subscription operations for a MemexProject.
class MemexProject
  class NotifydSubscriptions
    attr_reader :actor, :project

    MemexOwner = T.type_alias { T.any(Organization, User) }

    sig { params(actor: User, project: MemexProject).void }
    def initialize(actor, project)
      @actor = actor
      @project = project
    end

    sig { returns(T::Boolean) }
    def viewer_is_subscribed?
      status = Notifyd::Subscriptions.subscription_status(actor, project.owner, project)
      status.respond_to?(:subscribed?) ? status.subscribed? : false
    end

    sig { returns(Notifyd::Responses::Boolean) }
    def subscribe
      Notifyd::Subscriptions.subscribe_to_thread(actor, project.owner, project, "manual")
    end

    sig { returns(Notifyd::Responses::Boolean) }
    def unsubscribe
      Notifyd::Subscriptions.unsubscribe_from_thread(actor, project)
    end
  end
end
