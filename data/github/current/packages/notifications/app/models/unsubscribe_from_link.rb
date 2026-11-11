# typed: true
# frozen_string_literal: true

# Puts together unsubscription mechanism for newsies an notifyd.
class UnsubscribeFromLink
  attr_reader :auth, :resource

  def initialize(action, token)
    @action = action
    @newsies = Newsies::UnsubscribeFromLink.new(action, token)
    @notifyd = Notifyd::UnsubscribeFromLink.new(action, token)
    @auth, @resource = prepare
  end

  # This method checks by order whether a token is valid for newsies and
  # notifyd, if none are valid then it returns a null response that
  # unauthorizes all operations.
  #
  # NOTE: At the moment of signing, each token uses an action name that
  # includes the signer, that's why a token for `notifyd` can't be valid for
  # `newsies` and viceversa.
  def prepare
    newsies_auth, newsies_resource = newsies.prepare
    if newsies_auth.valid?
      instrument(auth: newsies_auth, resource: newsies_resource, verifier: :newsies)

      return newsies_auth, newsies_resource
    end

    notifyd_auth, notifyd_resource = notifyd.prepare
    if notifyd_auth.valid?
      instrument(auth: notifyd_auth, resource: notifyd_resource, verifier: :notifyd)

      return notifyd_auth, notifyd_resource
    end

    instrument(auth: newsies_auth, resource: newsies_resource)

    [newsies_auth, newsies_resource]
  end

  def unsubscribe
    resource.unsubscribe(auth.user)
  end

  private

  attr_reader :action, :newsies, :notifyd

  def instrument(auth:, resource:, verifier: :none)
    GitHub.dogstats.increment(
      "notifications.subscriptions.unsubscribe_from_link",
      tags: ["verified_by:#{verifier}", "action:#{action}"]
    )
    GitHub.logger.info("unsubscribe_from_link", {
      "code.namespace" => "UnsubscribeFromLink",
      "code.function" => "prepare",
      "gh.catalog_service" => "github/notifications",
      "gh.notifications.action" => action,
      "gh.notifications.service" => verifier,
      "gh.notifications.thread.type" => resource&.thread&.class || "",
      "gh.notifications.thread.id" => resource&.thread&.try(:id) || ""
    })
    if FeatureFlag.vexi.enabled?(:notification_email_unsubscribe_click_tracking, default: false)
      GlobalInstrumenter.instrument(
        "notifications.user_action",
        user: auth&.user,
        list_type: Newsies::List.to_type(resource&.thread&.notifications_list).to_s,
        list_id: resource&.thread&.notifications_list&.id,
        thread_type: Newsies::Thread.to_type(resource&.thread).to_s,
        thread_id: resource&.thread&.try(:id),
        handler: :EMAIL,
        action: :LINK_CLICK,
        metadata: {
          "event" => "footer_unsubscribe_link_click",
          "action" => action,
          "service" => verifier,
          "is_pull_request" => (resource&.thread.try(:pull_request_id).present?).to_s,
          "subject_type" => resource&.try(:subject_type).to_s
        }
      )
    end
  end
end
