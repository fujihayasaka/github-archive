# Enable integrators to use Notifyd delivery pipeline

## Background

The integrator can integrate with notifications by passing the events the user has to be notified about through the Notifyd pipeline. On the diagram below you see the pipeline for `issue.labeled` event.

![Image](https://github.com/github/notifyd/assets/1885174/719c501c-eb7f-4c9f-9421-fb014b71a5ae)

1. First, the event has to be produced in the code. For that standard Rails ActiveSupport::Notifications mechanism is used. On this stage we add the data we will need later in the pipeline to the event. That's how it looks like in case of issues:

```ruby
  def instrument_event_for_hydro
    return unless HYDRO_EVENTS.include?(event)
    return if skip_hydro_event_instrumentation

    payload = {
      actor: safe_actor,
      issue: issue,
      repository: issue.repository,
      repository_owner: issue.repository.owner,
      pull_request: issue.pull_request,
      event: self,
    }

    if event == "labeled"
      payload[:label] = label
    end

    GlobalInstrumenter.instrument "issue.events.#{event}", payload
  end
```

2. Every event may have multiple listeners. We subscribe to the issue events we process via Notifyd in `config/instrumentation/hydro/subscriptions/notifyd_issues.rb`:

```ruby
subscribe("issue.events.labeled") do |payload|
    issue = payload[:issue]
    event = payload[:event]
    next unless issue
    next unless event
    actor = payload[:event]&.actor
    next unless actor

    Notifyd::NotifyPublisher.new.async_publish(
      actor_id: actor.id,
      subject_id: issue.id,
      subject_klass: issue.class.name,
      context: {
        actor_id: actor.id,
        actor_login: actor.display_login,
        operation: Notifyd::Operations::IssueOperation::Labeled.serialize,
        added_label_id: event.label_id,
        explicit_auto_subscriptions: check_explicit_auto_subscriptions.call(issue, actor),
        event_id: event.id,
      })
  end
```
On this stage we fetch additional data based on the data from the event and pass it to `NotifyPublisher.async_publish`.

3. As building the notification message may take some time it is done in a background. NotifyPublisher.async_publish schedule `ProcessNotifyMessageJob` execution where the event data is processed by a custom logic to build a NotifyMessage to be consumed by Notifyd.

4. After message is build it is pushed to the hydro queue.
5. From Hydro the message is consumed by the Notifyd consumer and processed further.

## Current code architecture

For this proposal we're concentrating on the steps 2 and 3 as it's where the customizations are involved the most.

On stage 2 integrator has to decide if they need to include some additional data to the context parameter. This depends on what data they need to be present in notification message. For issue labeled event it is  `added_label_id` as it's going to be used as one of the attributes of the `NotifyMessage`.

After we passed all the data we need to `NotifyPublisher` the next point in the pipeline where integrator has to customize things is adapters. Adapters are used to transform the event data passed to NotifyPublisher to NotifyMessage which will be send to the queue consumed by notifyd.

That's how the construction of NotifyMessage looks like now:

```ruby
    args = {
    actor_id: actor_id,
    repository_id: adapter.repository_id,
    owner_id: adapter.owner_id,
    owner_type: adapter.owner_type,
    authzd_attributes: adapter.authzd_attributes,
    saml_enforcement: adapter.saml_enforcement,
    mobile_layout: adapter.mobile_layout,
    email_layout: adapter.email_layout,
    explicit_recipients: adapter.explicit_recipients,
    subject: subject,
    related_topics: adapter.related_topics,
    triggered_at: triggered_at,
    trigger: adapter.trigger,
    attributes: adapter.attributes,
    feature_switches: adapter.feature_switches,
    reason_groups: adapter.reason_groups,
    }
```

Adapter is chosen based on a subject field of the event data: 
```ruby
adapter = Notifyd::SubjectAdapter.adapter_for_subject(subject, context)
```

The integrator must implement the custom adapter for its subject if it does not exist yet. If the subject adapter already exists, but integrator wants to add another event - for example, for issues, they need to adjust the code of the existing adapter.

## The problems of current approach

The approach described above has both advantages and disadvantages. On one hand, it's customizable and we won't want to lose that. On the other hand, several things can be improved, among them:

**1. Complexity of customizing the Notifyd pipeline for newly added events.**

 It is not very intuitive to implement custom subject adapter. Integrators need some code studying before establishing the connection between adapters code and notifyd message. Apart from that, it requires to implement lots of methods that might be not needed in case of a particular integration. If integrator has to add new issue event, for example, it gets even uglier: they need to modify very long (and messy) issue adapter trying to not to break our existing flows.

**2. Absence of clear contracts and building blocks exposed to the integrators.**

Despite making integrator implement long list of methods in a subject adapter we have no clear contracts as to what structures are considered valid by our system. We do not have any structured approach to validation of the structures created by the integrators that they can utilize when testing their changes in isolation. Currently integrators has to construct Protobuf models directly without any middle layer.

**3. Customization is done on subject-level rather than on the event level.**

Adapter is chosen by the subject which leads to owercrowded, over-complicated and messy adapters if there are a lot of events related to the subject. Good example is issue_adapter. It would be easier to comprehend the logic if it's split. Therefore we should give an integrator an option to customize their processing based on the event.

**4. All of the 3 problems above are exacerbated by the lack of clear integration guidelines.**

It would be much easier for integrators if we had a documentation. However, it's not so easy to document current state of our pipeline. Addressing the problems above should help to create the guidelines that are easier to comprehend.

## Proposed solution

### Contracts

We start with creating a middle layer that is easier for us to control. The middle layer shall be used by integrators to construct notify message and shall include validation. The middle layer should be part of our ruby gem and therefore it cannot be dependent on GitHub modules or classes and we should be careful not to mix GitHub and Notifyd entities. 

The POC of middle layer can be found in this branch: https://github.com/github/notifyd/pull/3666/files


**Notifyd::Event**

Wrapper for the event data. It contains mandatory fields that are validated as well as context which is a hash map modifiable by integrators. 

**Notifyd::Entity**

This is an interface that every object in the middle layer must implement.
It contains two methods:

```
sig { void }
def validate; end

sig { void }
def to_proto; end
```

`validate` contains a validation logic and throws and exception if the object fails to pass validation.

`to_proto` method serializes object to protobuf.

**Notifyd::NotifyMessage**

Wrapper for `NotifyMessage`. Using this class it should be possible to construct `NotifyMessage` in GitHub code. 


**Notifyd::NotifyMessage:: classes**

Classes under notify_message represent building blocks of a message with their own validation logic and accessors. For example `Notifyd::NotifyMessage::Authorization` to construct authorization field.


### Changes in the transformation part of the pipeline

Once we updated our ruby gem to include middle layer objects we can think of the ways to solve the remaining two problems. The code fragments that will follow are taken from the POC branch in monolith: https://github.com/github/github/pull/302656/files

**Constructing an event in listener**

First stage where the intervention is needed is a construction of the event itself and adding all the data we will need down the pipeline. For that we can use `Notifyd::Event` wrapper instead of passing set of parameters to `NotifyPublisher``:

```ruby
  subscribe("issue.events.labeled") do |payload|
    issue = payload[:issue]
    event = payload[:event]
    next unless issue
    next unless event
    actor = payload[:event]&.actor
    next unless actor

    Notifyd::NotifyPublisher.new.async_publish_v2(Notifyd::Event.new(
      actor_id: actor.id,
      subject_id: issue.id,
      subject_klass: issue.class.name,
      notification_builder_klass: Notifyd::NotificationBuilders::IssueLabeledNotification.name,
      context: new Notifyd::Event::Context(
        actor_id: actor.id,
        actor_login: actor.display_login,
        operation: Notifyd::Operations::IssueOperation::Labeled.serialize,
        event_id: event.id,
        additional_data: {
          added_label_id: event.label_id,
          explicit_auto_subscriptions: check_explicit_auto_subscriptions.call(issue, actor),
        }
      ) do |additional_data| {
        !additional_data["added_label_id"].nil? && !additional_data["explicit_auto_subscriptions"].nil?
      })
  end
```

The `Notifyd::Event` will be validated by our gem. The constructed event has an interface that integrator can use to fetch the data from the event. Notice that event has a new field `notification_builder_class` that contains the name of the class that will be responsible for the construction of `NotifyMessage` for this event.


**Transforming event to NotifyMessage**

This part is a bit more complicated. The most work is happening on this stage. Our goal is to fill NotifyMessage with the  data we want to pass to Notifyd. As an input we have a `Notifyd::Event`.

To give an idea how it could look like in POC I created a class responsible for transforming `Notifyd::Event` to `NotifyMessage` object:

```ruby
module Notifyd
  class EventToNotificationMessageConverter
    attr_reader :event, :subject, :message_builder

    class MalformedEventError < StandardError; end
    class SubjectMissingError < StandardError; end


    def initialize(notifyd_event)
      raise MalformedEventError unless notifyd_event.valid?
      assert_subject_present { subject = notifyd_event.subject_class.constantize.find_by_id(@event.subject_id) }
      actor = User.find(notifyd_event.actor_id)

      if !event.repository_id.nil?
        repository = Repository.find(event.repository_id)
      end

      @message_builder = @event.message_builder_class.constantize.new(notifyd_event, subject, repository, actor)
    end

    def assert_subject_present(&block)
      raise SubjectMissingError unless yield
    end

    def convert
      message_builder.build_notifyd_message
    end
  end
end
```

This class is a helper class that has two purposes:

1. Fetch all the objects needed to form the notification from database: subject, repository, actor.
2. Dispatch to the message builder specified in the event that will construct NotifyMessage based on `Notifyd::Event` object, subject, repository and actor as input.

The example of custom message builder for "issue labeled" event from POC:

```ruby
module Notifyd
  module NotificationBuilders
    class IssueLabeledNotification < Default
      def build_notify_message
        notification = Notifyd::NotifyMessage.new(event) do |builder|
          builder.use_repository_id(event.repository_id)
          .use_attribute("added_label_id", event.context["added_label_id"])
          .use_attribute("thread-participant_activity", "true")
          .use_topic("repository", event.context["repository_id"])
          .use_topic(subject.thread_type, subject.thread_id)
          .use_owner(repository.owner.id, repository.owner.type)
          .use_authzd_attributes(subject.permissions_wrapper.serialized_subject_attributes)
          .use_email_layout(email_layout)
          .use_mobile_layout(mobile_layout)
          .use_notification_id(subject.permalink(include_host: false))
        end

        notification.to_proto
      end

      private

      def mobile_layout
        return unless actor

        MobileRenderer::Issue
          .new(issue: subject, author: MobileRenderer::AuthorUser.new(user: actor))
          .render
      end

      def email_layout
        author = actor.present? ? Email::AuthorUser.new(user: actor) : Email::NullAuthor.new

        Email::IssueRenderer.new(issue: subject, author: author, operation: event.trigger, context: event.context).render
      end
    end
  end
end
```

Custom builders can share some code via common ancestor:

```ruby
module Notifyd
  module NotificationBuilders
    class Default
      extend T::Sig
      class ValidationError < StandardError; end

      attr_reader :event, :subject, :repository, :actor

      def initialize(event, subject, repository, actor)
        @event = event
        @subject = subject
        @repository = repository
        @actor = actor
      end

      def build_notify_message
        raise NotImplementedError.new("Descendants must implement #build_notify_message")
      end
    end
  end
end

```

Our code in `PublishNotifyMessageJob` shall only call the converter and pass the constructed message to Notifyd:

```ruby
    def perform(event_parameters)
      event = Notifyd::Event.new(event_parameters)

      notify_message = begin
        Notifyd::EventToNotificationMessageConverter.new(event).convert
      rescue StandardError => e
        GitHub.logger.error(message: "Failed to convert event to notify message", exception: e)
      end

      Notifyd::NotifyPublisher.new.publish_v2(notify_message)
    end
```

## Conclusion

As a result of implementing the proposed solution we will get the following advantages:

1. Integrator can interact with Notifyd entities via contracts that can be documented and type checked and that contain validation.
2. Integrator can customize their notifications on the event basis which will help to simplify custom adapters/builders.
3. The proposed pipeline customization process is easier to follow than current one and can be documented to reduce our investment in integrations.
4. The proposed solution does not interfere with the current implementation and can be used for new events. Old events can gradually migrate to new pipeline.

