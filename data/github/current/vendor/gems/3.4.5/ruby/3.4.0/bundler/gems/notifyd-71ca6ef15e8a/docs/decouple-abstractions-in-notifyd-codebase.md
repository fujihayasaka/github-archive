
## [Brief] Notifyd codebase has leaky abstractions that are hard to scale #663 

## Problem statement 
Current `notifyd` codebase has tightly coupled abstractions and are hard to navigate at this point.

Main problems with codebase I see at the moment:

### 1. Leaky abstractions

We have 2 examples where I see the most problems:
- `*Handler` classes - those classes are carrying too much responsibility (validating message, doing auth, checking dotcom policies, publishing stuff) and I personally have big troubles navigating them
- `*Consumer` classes - those entry points have to constuct every single dependency for the project and pass it to `*Handler` class. Example https://github.com/github/notifyd/blob/47ad970d673e5d8fdda4ee78fe8084202c850728/cmd/notify-consumer/notify-consumer.go#L108

Handler and Consumer are handling 80% of domain application logic and we need better way to structure our domain code.

### 2. Unclear package names

Main problem that I see with package names is that it's hard to separate domain code (policy checkers, auth, etc) from general purpose code (logging, utils, stats)
- every time it takes me extra time to differ domain specific packages from general purpose ones
- it's unclear where to create new packages

3) Entry point of the application needs to know how to build every single dependency for the project
As an example see [`cmd/notify-consumer.go`](https://github.com/github/notifyd/blob/c71b720aba157245e3a5a5bdbc4e4761493d9c80/cmd/notify-consumer/notify-consumer.go#L46) file. It's not responsiblity of entry point to explicitly initialize entire application.
Problem with this approach that if we introduce 10 more dependencies this approach isn't going to scale.

Another example suggested by @almaleksia:

https://github.com/github/notifyd/blob/47ad970d673e5d8fdda4ee78fe8084202c850728/cmd/notify-consumer/notify-consumer.go#L82-L106

This code is constructing bunch dependencies before passing them to handler, which is already an indication that we need a module that would manage dependency injection.


Based on reasons above I have strong feeling that we need to split up our delivery pipeline and describe it with more granular and composable abstractions.
That's why I decided to create [Go Playground](https://github.com/github/go-notifications-playground) compilable prototype that covers `notify-consumer` application to 100% of it's functionality. 

### Goals

- Create explicit scalable abstractions that we could reuse and scale in the future
- Enable simplier testing for isolated abstractions
- Increase testability of the code. DI should help us to test negative flows more efficient.

### Non goals

- **We won't need to rewrite entire notifyd codebase, here we are talking about code structure problems. Most of the codebase will remain exactly the same.**
- Doesns't solve any of our architectural problems. Implementation, however simplifies couple of possibilies to solve Kafka message retries or building non-blocking consumers.
- Doesn't solve our problems on storage layer, we don't introduce any `Repository-like` patterns, but it's going to become easier.
