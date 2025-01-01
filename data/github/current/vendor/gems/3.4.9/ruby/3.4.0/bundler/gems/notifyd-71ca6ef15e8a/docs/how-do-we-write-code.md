# How do we write code

## We follow existing style guides

We follow the conventions and style defined by [Effective Go][effective-go] and Google's [Go Style Guide][go-style-guide].

## Adding new packages

For sanity of our codebase we want to adopt some rules that help us isolate
components and make boundaries between them clear.

- `internal/` follows the same structure than `cmd`. All the binaries that use
  additional packages apart from main should have an entry in `internal/`
- packages that are isolated and used exclusively by some program should be
  internal to that program: e.g. `internal/mobile/text`
- shared packages are moved to `internal/pkg`, following the conventions in
  [Standard Layout][standard-layout]
- Use [go conventions][package-names] for package names

### Recommended reads

- https://rakyll.org/style-packages/

### More on the motivation for this

- https://github.com/github/notifyd/discussions/1732

## We use dependency injection

Dependency injection is a design pattern that consists on an object receiving
all the other objects that it needs to work.

Imagine for example this code:

```go
type Service struct {}

func (s *Service) CreateUser(user User) error {
  cfg, err := config.Load()
  if err != nil {
    return err
  }

  db, err := cfg.GetDBConnection()
  if err != nil {
    return err
  }

  validator := NewUserValidator()
  if err := validator.IsValid(user); err != nil {
    return err
  }

  storage := NewUserStorage(db)
  return storage.Create(user)
}
```

This has 2 big problems:

1. It depends on 4 different other objects (config, db connection, validator
   and user storage). If any of those changed the way they are built or
   included additional dependencies the change would cascade into your
   `CreateUser` method, forcing you to change it and aggravating the problem.
1. It is hard to test:
   - It depends on the database which forces you to depend on a database to test it.
   - It needs to load the config object, which normally depends on env variables.

Instead, dependency injection proposes a different approach.

```go
type Service struct {
  storage *UserStorage
}

func (s *Service) CreateUser(user User, validator UserValidator) error {
  if err := validator.IsValid(user); err != nil {
    return err
  }

  return storage.Create(user)
}
```

In this code we make some change that transform our previously implicit
dependencies into explicit ones.

This has some advantages:

- The things it depends on are more explicit, and they are easily swappable by
  interfaces instead of structs. Depending on an `interface` instead of a
  `struct` is beneficial because we are no longer limited to a single
  implementation, it makes testing easier but it also allows us to iterate on
  implementation details without having to cascade changes everywhere. In other
  words, makes the code Open/Closed (Open for extension and closed for
  modifications)
- The `CreateUser` method no longer needs to know all the boilerplate to create
  each one of its dependencies, which makes cascading changes less likely to
  appear, this results in loosely coupled objects that are easier to manage.

This boilerplate, however, does not disappear, it still needs to be written
somewhere and then used to construct our `Service`.

## We construct the dependency graph in the main package.

We used to use [`wire`][wire] to build and connect the different components in the dependency graph.
This has some problems. An example can help visualize some of them:

```go
// internal/api/newsies/wire_gen.go
func BuildServer(clockClock clock.Clock, provider *telemetry.Provider, client stats.Client, db mysql.DB, featureflagsClient featureflags.Client) (*Server, error) {
	service, err := newsies.BuildService(clockClock, provider, client, db, featureflagsClient)
	if err != nil {
		return nil, err
	}
	server := New(service, provider)
	return server, nil
}

// internal/newsies/wire_gen.go
func BuildService(clockClock clock.Clock, provider *telemetry.Provider, client stats.Client, db mysql.DB, featureflagsClient featureflags.Client) (*Service, error) {
	settingsService, err := routing.BuildService(clockClock, provider, client, db, featureflagsClient)
	if err != nil {
		return nil, err
	}
	subscriptionService, err := subscriptions.BuildService(clockClock, provider, db, featureflagsClient)
	if err != nil {
		return nil, err
	}
	service := NewService(settingsService, subscriptionService, client, clockClock)
	return service, nil
}

// internal/pkg/routing/wire_gen.go
func BuildService(clockClock clock.Clock, provider *telemetry.Provider, client stats.Client, db mysql.DB, featureflagsClient featureflags.Client) (*SettingsService, error) {
	routingStorage := NewStorage(clockClock, provider, db, featureflagsClient)
	settingsService := NewService(routingStorage, provider, client)
	return settingsService, nil
}
```

In the above example it can be seen how the components are built all along the dependency graph.
This means that in order to undertand or modify the dependency graph, all the components spread out around all the different packages need to be considered.
At it can be seen in the example, if the routing settings storage requires a new dependency (e.g. a feature flags client), all the dependency graph must be changed.

For comparison, consider how the dependency graph can be built in the main package:

```go
// cmd/api/main.go
func main() {
  // clock, telemetry provider, db, featureflags client, etc. dependencies are already built.
  routingStorage := routing.NewStorage(clock, telem, db, features)
  routingService := routing.NewService(routingStorage, telem, statter)
  subscriptionsStorage := subscriptions.NewStorage(clock, telem, db, features)
  subscriptionsService := subscriptions.NewService(routingStorage, telem, statter)
  newsiesService := newsies.NewService(routingService, subscriptionService, statter, clock)
  server := newsiesserver.New(service, telem)
}
```

All the dependency graph is now built in a single place and it's easier to follow. Changing a dependency in a single component (e.g. adding or removing the feature flags client) is now easier too.
Additionally, a lot of unnecessary error handling is now gone.

There's still some code built in the former way but it will eventually be converted to the new approach. All the new code should follow the new approach. If you find some code in the old approach that can be easily converted, please don't hesitate to do so.

[effective-go]: https://go.dev/doc/effective_go
[go-style-guide]: https://google.github.io/styleguide/go/
[wire]: https://github.com/google/wire
[standard-layout]: https://github.com/golang-standards/project-layout#internal
[package-names]: https://go.dev/doc/effective_go#package-names
