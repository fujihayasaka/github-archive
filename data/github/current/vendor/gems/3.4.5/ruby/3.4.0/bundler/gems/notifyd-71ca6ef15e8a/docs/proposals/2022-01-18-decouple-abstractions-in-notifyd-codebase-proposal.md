# Overview

As outlined in the [brief](https://github.com/github/notifyd/pull/663/files?short_path=ff84427#diff-ff844278ae8172a5ce5e287acf21ce63b5fdd105c3b85baf98cd725321d51e8a) we would like to introduce explicit, scalable abstractions in notifyd codebase that carry less responsibility, are easier to test and can be better composed.

For that we suggest to restructure existing code for Notifyd, change how we initialize project at the entry point with dependency injection and organize the existing code into clearer abstractions.

## Expected outcome:
- Codebase has clear testable abstractions that are not overloaded with responsibilities. 
- Package naming is clear for end user and separates domain logic from util code. 


# Proposed solution

## Naming and Abstractions

First we could start with package naming:
- **domain** 
- **platform**
- **handlers**
- **stages**

Below you can find description for each package name. 

### Domain

This package just contains `clients`/`services` logic that can be related to our domain model. 
**Examples**: `authzd-client`, `dotcom_checker`, `email_sender`, `subscriptions_service`, etc.
Main objective is to separate domain logic from everything else. 

### Platform
Platform package is meant to contain everything that isn't domain specific - logging, interation with hydro, feature flags, DB specific logic, errors, config. 

### Handlers
**Handlers** is our new main abstraction here - most of `notifyd` logic transforms original `Notify` message into concrete `emails`, `push` and in the future other notifications by doing bunch of data transformations in the delivery handler.

We can think of 3 handlers a this point:

```
notify-consumer handlers --> deliver-push-consumer handler 
                         --> email-consumer handler 
```

but there might be more: `notifyd-consumer-retry-deadletter-handler`, `priority-email-handler`, in case if we want to introduce retries separate queues, etc.

### Stages
This is another important concept. Each handler contains a set of **Stages**. 

**Stage** is composable and potentially reusable chunk of work, for example:
- calculating recipients
- authorizing recipients
- verifying policies

This approach looks very similar to **Command** pattern and looks quite extensible - we can define as many **Stages** as we need and compose new or alter existing **Handler** in the matter of days not weeks!

Also as some point we thought of defining handlers via configuration files - with Stages it should be also theoretecally possible.

### (Not included in this proposal) Controllers/API handlers
For API use-case possible alternative would be introducing controllers/API handlers.


### Packages Example
Here is example how packages could be structured:
![image](https://user-images.githubusercontent.com/5173831/151367621-edfcb5cc-6ed4-44c8-bf63-afaad5bf5ebc.png)

Please checkout live code here (this prototype covers 80% notifyd codebase): https://github.com/github/go-notifications-playground


## How handlers/stages supposed to work?

This diagram shows how notification will travel through Handlers stages flow:
![image](https://user-images.githubusercontent.com/5173831/151368719-3b31c2be-0d76-4476-8fa2-766b651895fd.png)

also you can find examples in the code here:
https://github.com/github/go-notifications-playground/blob/master/internal/pipeline/notify/notify_pipeline.go

```go
func (handler *NotifyHandler) Process(ctx context.Context, msg entities.Notify) error {
	actorID := msg.GetActor().GetId()
	notificationID := msg.GetNotificationId()

	ctx = o11y.CtxSetNotificationID(ctx, notificationID)
	ctx = o11y.CtxSetActorID(ctx, int64(actorID))

	logger := handler.loggerContainer.WithDefaultTags(ctx)
	logger.Info("processing Notify message")

	recipientIDsToReasons, err := handler.PrepareRecipients(ctx, msg, actorID)
	if err != nil {
		return nil
	}

	handler.schedulePushNotificationsStage.Execute(ctx, recipientIDsToReasons, msg)
	err = handler.scheduleEmailNotificationsStage.Execute(ctx, recipientIDsToReasons, msg)
	if err != nil {
		// do nothing other than reporting, not emails were sent here because of FF client errors
	}

	return nil
}

func (handler *NotifyHandler) PrepareRecipients(ctx context.Context, msg entities.Notify, actorID int32) (common.RecipientIDToReasons, error) {
	recipientIDsToReasons, err := handler.calculateRecipientsStage.Execute(ctx, actorID, msg)
	if err != nil {
		return nil, err
	}

	// authorizing based on policies defined in dotcom
	authorizedRecipientIDsToReasons, err := handler.authorizeRecipientsStage.Execute(ctx, recipientIDsToReasons, msg)
	if err != nil {
		return nil, err
	}

	handler.authorizeRecipientsStage.Cleanup()
	verifiedRecipientsIDsToReasons, err := handler.validateDotcomRecipientPoliciesStage.Execute(ctx, authorizedRecipientIDsToReasons, msg)
	if err != nil {
		return nil, err
	}
	return verifiedRecipientsIDsToReasons, nil
}

func (handler *NotifyHandler) Cleanup() {
	handler.calculateRecipientsStage.Cleanup()
	handler.authorizeRecipientsStage.Cleanup()
	handler.validateDotcomRecipientPoliciesStage.Cleanup()
	handler.schedulePushNotificationsStage.Cleanup()
	handler.scheduleEmailNotificationsStage.Cleanup()
}
```


## Patterns considerations

#### Dependency injection
In this proposal is suggested to use dependency injection because it can help us to simplify entry point logic for our applications, testing and configuring, mock dummy dependencies used for testing/different environments.

Concept of inversion of control: https://stackoverflow.com/questions/3058/what-is-inversion-of-control
Go example: https://blog.drewolson.org/dependency-injection-in-go

Talk about DI in Go context https://www.youtube.com/watch?v=LDGKQY8WJEM

#### Handler/Pipeline pattern
Ms docs good example: https://docs.microsoft.com/en-us/previous-versions/msp-n-p/ff963548(v=pandp.10)

## New Libraties used
Wire DI - https://github.com/google/wire/blob/main/docs/guide.md

**Why Wire?**
There are 2 main approaches for dependency injection - finding our dependencies in runtime or compile time. 
Complie time DI is preferred because it avoids unnessessary runtime misconfiguration errors, even if we need to write a bit more code for that:
- DI solution is not likely to introduce errors to the production app
- We can rely on Go complier (even before tests!) to tell us where we made a mistake configuring depdencies

Wire seemed to be the best option for compile time DI, but IMO we can switch to any other DI framework (Dig, Fx, you name it) if we decide otherwise.

## Migration path for Notifyd
I acknowlege that this change may look too dramatic to bring it to our current Notifyd, but I beleive there is path to introduce all those changes gradually:

1) Add support for DI container `wire` in this case. It will allow to start onboarding existing dependencies PR - https://github.com/github/notifyd/pull/657
2) Iteratively onboard enough dependencies to `wire` DI context
3) Make single `internal/consumer/consumer.go` class to rely completely on DI provided dependencies
4) Split logic inside of `internal/consumer/consumer.go` into `Stages` classes that will reuse dependencies from DI 
