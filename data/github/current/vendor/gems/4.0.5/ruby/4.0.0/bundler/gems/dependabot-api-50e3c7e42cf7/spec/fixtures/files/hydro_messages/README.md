#### Hydro Fixtures

These fixtures are a JSON representation of the messages we consume from Hydro that **include only the keys we actually use**.

They are loaded used using a test helper like so:

```ruby
hydro_fixture(schema: "gitub.v1.FooEvent", name: "happy_path")
```

This will load the JSON in `github.v1.FooEvent/happy_path.json` as a `HashWithIndifferentAccess` having parsed it using Hydro's encode and decode message to ensure the fixture is valid and correctly typed.
