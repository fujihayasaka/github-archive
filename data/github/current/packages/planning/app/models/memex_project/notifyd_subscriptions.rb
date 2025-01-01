# typed: true
# frozen_string_literal: true

# This class is a light wrapper around the Notifyd::SubscriptionsHelper class,
# providing methods to manage notification subscriptions for a MemexProject.
class MemexProject

  class NotifydSubscriptions
    extend T::Sig
    include GitHub::Memoizer

    attr_reader :actor, :project

    MemexOwner = T.type_alias { T.any(Organization, User) }

    sig { params(actor: User, project: MemexProject).void }
    def initialize(actor, project)
      @actor = actor
      @project = project
    end

    sig { returns(T::Boolean) }
    def viewer_is_subscribed?
      subscriptions.notifyd_subscription_status(actor, project.owner, project).subscribed?
    end

    sig { returns(Notifyd::Responses::Boolean) }
    def subscribe
      subscriptions.notifyd_subscribe_to_thread(actor, project.owner, project, "manual")
    end

    sig { returns(Notifyd::Responses::Boolean) }
    def unsubscribe
      subscriptions.notifyd_unsubscribe_from_thread(actor, project)
    end

    sig { returns(Notifyd::SubscriptionsHelper) }
    memoize private def subscriptions
      Notifyd::SubscriptionsHelper.new
    end
  end
end
